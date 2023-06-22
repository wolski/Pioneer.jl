
using Arrow, Tables, DataFrames, Dictionaries, Combinatorics, StatsBase, NMF, JLD2, LinearAlgebra, Random, DecisionTree
include("src/precursor.jl")
#include("src/buildFragmentIndex.jl")
include("src/Routines/LibrarySearch/buildFragmentIndex.jl")
include("src/Routines/LibrarySearch/matchpeaksLIB.jl")
include("src/Routines/LibrarySearch/NMF.jl")
include("src/Routines/LibrarySearch/spectralContrast.jl")
include("src/Routines/LibrarySearch/selectTransitions.jl")
include("src/Routines/LibrarySearch/searchRAW.jl")
include("src/Routines/LibrarySearch/queryFragmentIndex.jl")


@load "/Users/n.t.wamsley/Projects/PROSIT/prosit_detailed.jld2"  prosit_detailed
@load "/Users/n.t.wamsley/Projects/PROSIT/prosit_index_all.jld2"  prosit_index_all
@load "/Users/n.t.wamsley/Projects/PROSIT/prosit_precs.jld2"  prosit_precs

#@time PSMs = SearchRAW(MS_TABLE, prosit_index, prosit_list_detailed, UInt32(1))
#@time PSMs = SearchRAW(MS_TABLE, prosit_index, UInt32(1))
include("src/PSM_TYPES/PSM.jl")
include("src/PSM_TYPES/LibraryXTandem.jl")
#include("src/PSM_TYPES/FastXTandem.jl")
MS_TABLE = Arrow.Table("/Users/n.t.wamsley/RIS_temp/ZOLKIND_MOC1_MAY23/parquet_out/MA5171_MOC1_DMSO_R01_PZ.arrow")
@time PSMs = SearchRAW(MS_TABLE, prosit_index_all, prosit_detailed, UInt32(1))
MS_TABLE = Arrow.Table("/Users/n.t.wamsley/RIS_temp/MOUSE_DIA/ThermoRawFileToParquetConverter-main/parquet_out/MA5171_MOC1_DMSO_R01_PZ_DIA.arrow")
@time PSMs = SearchRAW(MS_TABLE, prosit_index_all, prosit_detailed, UInt32(1), precursor_tolerance = 4.25, fragment_tolerance = 40.0)

@time time_psms = SearchRAW(MS_TABLE, prosit_index_all, prosit_detailed, UInt32(1))

##########
#Get features
##########
using RobustModels
function refinePSMs!(PSMs::DataFrame, precursors::Vector{LibraryPrecursor}; loss::AbstractEstimator = TauEstimator{TukeyLoss}(), maxiter = 200, min_spectral_contrast::AbstractFloat = 0.8)
    transform!(PSMs, AsTable(:) => ByRow(psm -> isDecoy(precursors[psm[:precursor_idx]])) => :decoy)
    transform!(PSMs, AsTable(:) => ByRow(psm -> Float64(getIRT(precursors[psm[:precursor_idx]]))) => :iRT)
    transform!(PSMs, AsTable(:) => ByRow(psm -> Float64(MS_TABLE[:retentionTime][psm[:scan_idx]])) => :RT)
    transform!(PSMs, AsTable(:) => ByRow(psm -> psm[:weight] == 0) => :nmf)
    function predictRTs!(PSMs::DataFrame; loss::AbstractEstimator = TauEstimator{TukeyLoss}(), maxiter = 200, min_spectral_contrast::AbstractFloat = 0.8)
    
        targets = PSMs[:,:decoy].==false
        spectral_contrast = PSMs[:,:spectral_contrast].>=0.8#min_spectral_contrast
    
        best_matches = targets .& spectral_contrast
    
        #Predicted iRTs
        iRTs = hcat(PSMs[:,:iRT][best_matches], ones(Float32, sum(best_matches)))
        #Emperical retention times
        RTs = PSMs[:,:RT][best_matches]
    
        slope, intercept = RobustModels.coef(rlm(iRTs, RTs, loss, initial_scale=:mad, maxiter = maxiter))
    
        transform!(PSMs, AsTable(:) => ByRow(psm -> abs((psm[:iRT]*slope + intercept) - psm[:RT])) => :RT_error)

    end
    predictRTs!(PSMs, loss = loss, maxiter = maxiter, min_spectral_contrast = min_spectral_contrast)
end
refinePSMs!(PSMs, prosit_precs)

transform!(PSMs, AsTable(:) => ByRow(psm -> getCharge(precursors[psm[:precursor_idx]])) => :charge)
########
#
########
function rankPSMs!(PSMs::DataFrame, n_folds::Int = 5)
   
    X = Matrix(PSMs[:,[:hyperscore,:total_ions,:y_ladder,:b_ladder,:intensity_explained,:error,:poisson,:spectral_contrast,:spectrum_peaks,:nmf,:weight,:RT_error]])
    X_labels = PSMs[:, :decoy]
    permutation = randperm(size(PSMs)[1])
    fold_size = length(permutation)÷n_folds

    folds = [((n-1)*fold_size + 1):(n*fold_size) for n in range(1, n_folds)]

    PSMs[:,:prob] = zeros(Float64, size(PSMs)[1])

    for test_fold_idx in range(1, n_folds)
        println(test_fold_idx)
        train_fold_idxs = vcat([folds[fold] for fold in range(1, length(folds)) if fold != test_fold_idx]...)
        #println("train_fold_idxs ", train_fold_idxs)
        train_features = X[train_fold_idxs,:]
        train_classes = X_labels[train_fold_idxs,1]
        model = build_forest(train_classes, train_features, 4, 1000, 0.5, 3)
        probs = apply_forest_proba(model, X[folds[test_fold_idx],:],[true, false])
        PSMs[folds[test_fold_idx],:prob] = probs[:,2]
    end
    #model = build_forest(X_labels, X', 4, 2000, 0.5, 3)
    #probs = apply_forest_proba(model, X',[true, false])
    #PSMs[:,:prob] = probs[:,2]
end
@time rankPSMs!(PSMs)
train = randperm(size(PSMs)[1])[1:60000]
X = Matrix(PSMs[train,[:hyperscore,:total_ions,:y_ladder,:b_ladder,:intensity_explained,:error,:poisson,:spectral_contrast,:spectrum_peaks,:nmf,:weight,:RT_error]])
X_labels = PSMs[train, :decoy]
model = build_forest(X_labels, X, 4, 1000, 0.5, 3)
X = Matrix(PSMs[:,[:hyperscore,:total_ions,:y_ladder,:b_ladder,:intensity_explained,:error,:poisson,:spectral_contrast,:spectrum_peaks,:nmf,:weight,:RT_error]])
probs = apply_forest_proba(model, X,[true, false])
PSMs[:,:prob] = probs[:,2]
function getQvalues!(PSMs::DataFrame, probs::Vector{Float64}, labels::Vector{Bool})
    #Could bootstratp to get more reliable values. 
    q_values = zeros(Float64, (length(probs),))
    order = reverse(sortperm(probs))
    targets = 0
    decoys = 0
    for i in order
        if labels[i] == true
            decoys += 1
        else
            targets += 1
        end
        q_values[i] = decoys/(targets + decoys)
    end
    PSMs[:,:q_values] = q_values;
end
@time getQvalues!(PSMs, PSMs[:,:prob], PSMs[:,:decoy]);



histogram(PSMs[PSMs[:,:decoy].==true,:prob], alpha = 0.5)#, bins = -0.06:0.01:0.0)
histogram!(PSMs[PSMs[:,:decoy].==false,:prob], alpha = 0.5)#, bins = -0.06:0.01:0.0)


histogram(PSMs[PSMs[:,:decoy].==true,:q_values], alpha = 0.5)#, bins = -0.06:0.01:0.0)
histogram!(PSMs[PSMs[:,:decoy].==false,:q_values], alpha = 0.5)#, bins = -0.06:0.01:0.0)

histogram(PSMs[X_labels.==true,:prob], alpha = 0.5)#, bins = -0.06:0.01:0.0)
histogram!(PSMs[X_labels.==false,:prob], alpha = 0.5)#, bins = -0.06:0.01:0.0)

PSMs[PSMs[:,:precursor_idx] .== 3768665,[:weight,:RT]]

a = sort(PSMs[PSMs[:,:precursor_idx] .== 3768665,[:weight,:RT]], :RT)
plot(a[:,:RT], a[:,:weight], seriestype=:scatter)

a = sort(PSMs[PSMs[:,:precursor_idx] .== 421,[:weight,:RT]], :RT)
plot(a[:,:RT], a[:,:weight], seriestype=:scatter)

sort(counts,:nrow)

a = sort(PSMs[PSMs[:,:precursor_idx] .== 2526945 ,[:weight,:RT]], :RT)
plot(a[:,:RT], a[:,:weight], seriestype=:scatter)

a = sort(PSMs[PSMs[:,:precursor_idx] .== 717580 ,[:weight,:RT]], :RT)
plot(a[:,:RT], a[:,:weight], seriestype=:scatter)

a = sort(PSMs[PSMs[:,:precursor_idx] .==  2968051 ,[:weight,:RT]], :RT)
plot(a[:,:RT], a[:,:weight], seriestype=:scatter)


a = sort(PSMs[PSMs[:,:precursor_idx] .==   1894282      ,[:weight,:RT]], :RT);
plot(a[:,:RT], a[:,:weight], seriestype=:scatter)


sum(PSMs[X_labels.==true,:prob].>0.92)
sum(PSMs[X_labels.==false,:prob].>0.92)

unique(PSMs[PSMs[:,:prob].>0.92,:precursor_idx])


X = Matrix(PSMs[1:1:end,[:hyperscore,:total_ions,:y_ladder,:b_ladder,:intensity_explained,:error,:poisson,:spectral_contrast,:spectrum_peaks,:nmf,:weight,:RTdiff]])
X_labels = PSMs[:, :decoy]
@time model = build_forest(X_labels, X, 4, 100, 0.5, 3)
probs = apply_forest_proba(model, X',[true, false])
PSMs[:,:prob] = probs[:,2]
PSMs[:,:q_value] = getQvalues(PSMs[:,:prob], PSMs[:,:decoy])
histogram(PSMs[PSMs[:,:decoy].==true,:q_values], alpha = 0.5)#, bins = -0.06:0.01:0.0)
histogram!(PSMs[PSMs[:,:decoy].==false,:q_values], alpha = 0.5)#, bins = -0.06:0.01:0.0)

function getQvalues(probs::Vector{Float64}, labels::Vector{Bool}, bootstrap_n::Int = 1000)
    #Could bootstratp to get more reliable values. 
    order = reverse(sortperm(probs))
    q_values = zeros(Float64, (length(probs),))
    targets = 0
    decoys = 0
    for n in boostrap_n
        println(n)
        for i in order
            if labels[i] == true
                decoys += 1
            else
                targets += 1
            end
            q_values[i] += decoys/(targets + decoys)
        end
    end
    return q_values./bootstrap_n
end
PSMs[:,:q_values] = getQvalues(PSMs[:,:prob], PSMs[:,:decoy])

histogram(Ylda[X_labels.==true], alpha = 0.5, normalize = :pdf)#, bins = -0.06:0.01:0.0)
histogram!(Ylda[X_labels.==false], alpha = 0.5, normalize = :pdf)#, bins = -0.06:0.01:0.0)

plot(PSMs[X_labels.==true,:spectral_contrast], PSMs[X_labels.==true,:RTdiff], alpha = 0.5, seriestype=:scatter)#, bins = -0.06:0.01:0.0)

plot!(PSMs[X_labels.==false,:spectral_contrast], PSMs[X_labels.==false,:RTdiff], alpha = 0.5, seriestype=:scatter)#, bins = -0.06:0.01:0.0)


sum(Ylda[X_labels.==true].<-0.0085)
sum(Ylda[X_labels.==false].<-0.0085)

model = build_forest(X_labels, X', 4, 2000, 0.5, 3)
probs = apply_forest_proba(model, X',[true, false])
PSMs[:,:prob] = probs[:,2]


sortPSMs = sort(PSMs, :prob)

for 

histogram(PSMs[X_labels.==true,:prob], alpha = 0.5)#, bins = -0.06:0.01:0.0)
histogram!(PSMs[X_labels.==false,:prob], alpha = 0.5)#, bins = -0.06:0.01:0.0)


sum(PSMs[X_labels.==true,:prob].>0.92)
sum(PSMs[X_labels.==false,:prob].>0.92)

unique(PSMs[PSMs[:,:prob].>0.92,:precursor_idx])




using Dictionaries
using CSV, Arrow, Tables, DataFrames, StatsBase
include("src/precursor.jl")
#include("src/buildFragmentIndex.jl")
ms2s = MS_TABLE[:msOrder].==2

mean([length(MS_TABLE[:masses][i]) for (i, order) in enumerate(MS_TABLE[:msOrder]) if (order == 2)])


sort([length(MS_TABLE[:masses][i]) for (i, order) in enumerate(MS_TABLE[:msOrder]) if (order == 1)])
[i for i in  MS_TABLE[:msOrder]]