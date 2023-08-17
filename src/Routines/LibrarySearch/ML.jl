function getQvalues!(PSMs::DataFrame, probs::Vector{Union{Missing, Float64}}, labels::Vector{Union{Missing, Bool}})
    #Could bootstratp to get more reliable values. 
    q_values = zeros(Float64, (length(probs),))
    order = reverse(sortperm(probs)) #Sort class probabilities
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
    PSMs[:,:q_value] = q_values;
end

function getQvalues!(PSMs::DataFrame, probs::Vector{Float64}, labels::Vector{Bool})
    #Could bootstratp to get more reliable values. 
    q_values = zeros(Float64, (length(probs),))
    order = reverse(sortperm(probs)) #Sort class probabilities
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
    PSMs[:,:q_value] = q_values;
end

function rankPSMs!(PSMs::DataFrame, features::Vector{Symbol}; n_folds::Int = 3, colsample_bytree::Float64 = 0.5, num_round::Int = 25, eta::Float64 = 0.15, min_child_weight::Int = 1, subsample::Float64 = 0.5, gamma::Int = 0, max_depth::Int = 10, print_importance::Bool = false)
   
    #[:hyperscore,:total_ions,:intensity_explained,:error,:poisson,:spectral_contrast_all, :spectral_contrast_matched,:RT_error,:scribe_score,:y_ladder,:b_ladder,:RT,:diff_hyper,:median_ions,:n_obs,:diff_scribe,:charge,:city_block,:matched_ratio,:weight,:intensity,:count,:SN]
    X = Matrix(PSMs[:,features])
    X_labels = PSMs[:, :decoy]

    #Using a random selection of rows means that a pair strongly correlated rows (adjacent scans) could end up
    #split between the training and testing fold, potentially causing optimistic error estimates. Perhaps
    #this sampling scheme should be changed in the future?
    permutation = randperm(size(PSMs)[1])
    fold_size = length(permutation)÷n_folds

    #Get ranges for the cross validation folds. 
    folds = [((n-1)*fold_size + 1):(n*fold_size) for n in range(1, n_folds)]

    #Initialize class probabilisites
    PSMs[:,:prob] = zeros(Float64, size(PSMs)[1])
    #XGBoost model
    bst = ""
    for test_fold_idx in range(1, n_folds)
        train_fold_idxs = vcat([folds[fold] for fold in range(1, length(folds)) if fold != test_fold_idx]...)
        train_features = X[train_fold_idxs,:]
        train_classes = X_labels[train_fold_idxs,1]

        #Train a model on the n-1 training folds. Then apply it to get class probabilities for the test-fold. 
        bst = xgboost((train_features, train_classes), num_round=num_round, colsample_bytree = colsample_bytree, gamma = gamma, max_depth=max_depth, eta = eta, min_child_weight = min_child_weight, subsample = subsample, objective="binary:logistic")
        ŷ = XGBoost.predict(bst, X[folds[test_fold_idx],:])
        PSMs[folds[test_fold_idx],:prob] = (1 .- ŷ)
    end
    bst.feature_names = [string(x) for x in features]
    return bst
end

#=
CSV.write("/Users/n.t.wamsley/Projects/TEST_DATA/PSMs_072023_05.csv", PSMs)


PSMs = DataFrame(CSV.File("/Users/n.t.wamsley/Projects/TEST_DATA/PSMs_072023_04.csv"))

PSMs[isnan.(PSMs[:,:matched_ratio]),:matched_ratio] .= Inf
PSMs[(PSMs[:,:matched_ratio]).==Inf,:matched_ratio] .= 416119.4

features = [:hyperscore,:total_ions,:intensity_explained,:error,:poisson,:spectral_contrast_all, :spectral_contrast_matched,:RT_error,:scribe_score,:y_ladder,:b_ladder,:RT,:diff_hyper,:median_ions,:n_obs,:charge,:city_block,:matched_ratio,:weight,:kendall,:rank_hyper,:rank_poisson, :rank_scribe,:rank_total,:len]
@time bst = rankPSMs!(PSMs, features, colsample_bytree = 1.0, min_child_weight = 10, gamma = 10, n_folds = 3, num_round = 50, eta = 0.15)
@time getQvalues!(PSMs, PSMs[:,:prob], PSMs[:,:decoy]);
length(unique(PSMs[(PSMs[:,:q_value].<=0.01).&(PSMs[:,:decoy].==false),:precursor_idx]))
length(unique(PSMs[(PSMs[:,:q_value].<=0.1).&(PSMs[:,:decoy].==false),:precursor_idx]))


features = [:hyperscore,:total_ions,:intensity_explained,:error,:poisson,:spectral_contrast_all, :spectral_contrast_matched,:RT_error,:scribe_score,:y_ladder,:b_ladder,:RT,:diff_hyper,:median_ions,:n_obs,:charge,:city_block,:matched_ratio,:weight,:kendall,:rank_hyper,:rank_poisson, :rank_scribe,:rank_total,:len,:intensity,:count,:SN,:slope,:peak_error,:apex_error]
features = [:hyperscore,:total_ions,:intensity_explained,:error,:poisson,:spectral_contrast_all,:RT_error,:scribe_score,:y_ladder,:RT,:diff_hyper,:median_ions,:n_obs,:charge,:city_block,:matched_ratio,:weight,:kendall,:rank_hyper,:len,:intensity,:count,:SN,:slope,:peak_error,:apex_error]


best_psms = best_psms[(best_psms[:,:intensity].>0).&(best_psms[:,:count].>=5),:]
@time bst = rankPSMs!(best_psms, features, colsample_bytree = 1.0, min_child_weight = 10, gamma = 10, subsample = 1.0, n_folds = 5, num_round = 200, eta = 0.0375)
@time getQvalues!(best_psms, best_psms[:,:prob], best_psms[:,:decoy]);
length(unique(best_psms[(best_psms[:,:q_value].<=0.01).&(best_psms[:,:decoy].==false),:precursor_idx]))
#length(unique(best_psms[(best_psms[:,:q_value].<=0.1).&(PSMs[:,:best_psms].==false),:precursor_idx]))


best_psms = DataFrame(CSV.File("/Users/n.t.wamsley/Projects/TEST_DATA/best_psms_072223_03.csv"))
#["Targets ≤ 0.1% FDR",""
function plotStepHist(PSMs::DataFrame, group_a::BitVector, group_b::BitVector, column::Symbol, b_range::Any = nothing; normalize::Bool = true, transform::Any = x->x, title::String = "TITLE", label_a::String="Y1", label_b::String="Y2", f_out::String = "test.pdf")
    theme(:wong)
    p = plot(title=title, legend =:topleft);
    #b_range = range(0, 1, length=1000)
    stephist(p, transform.(PSMs[group_a,column]), bins = b_range, alpha = 1, normalize=normalize, labels = label_a)
    stephist!(transform.(PSMs[group_b,column]), bins = b_range, alpha = 1, normalize=normalize, labels =label_b)
    savefig(f_out)
end

targets = PSMs[:,:decoy].==false
decoys = PSMs[:,:decoy].==true
targets_01fdr = (PSMs[:,:decoy].==false) .& (PSMs[:,:q_value].<0.01)

plotStepHist(PSMs, targets, decoys, :prob, range(0, 1, length=1000), normalize = false, title = "Discriminant Score", label_a = "Targets", label_b = "Decoys", f_out = "/Users/n.t.wamsley/Projects/TEST_DATA/figs/discriminant_score.pdf")
plotStepHist(PSMs, targets, decoys, :q_value, range(0, 0.5, length=100), normalize = false, title = "Q-Value", label_a = "Targets", label_b = "Decoys", f_out = "/Users/n.t.wamsley/Projects/TEST_DATA/figs/q_value.pdf")
plotStepHist(PSMs, targets_01fdr, decoys, :spectral_contrast_all, range(0.5, 1, length=250), title = "Cosine Similarity Score", label_a = "Targets ≤ 0.1% FDR", label_b = "Decoys", f_out = "/Users/n.t.wamsley/Projects/TEST_DATA/figs/CSS.pdf")
plotStepHist(PSMs, targets_01fdr, decoys, :matched_ratio, range(-5, 10, length=1000), transform = x->log2(x), title = "Log2 Predicted Spectra Explained Ratio", label_a = "Targets ≤ 0.1% FDR", label_b = "Decoys", f_out = "/Users/n.t.wamsley/Projects/TEST_DATA/figs/matched_ratio.pdf")
plotStepHist(PSMs, targets_01fdr, decoys, :scribe_score, range(0, 20, length=1000), title = "Scribe Score", label_a = "Targets ≤ 0.1% FDR", label_b = "Decoys", f_out = "/Users/n.t.wamsley/Projects/TEST_DATA/figs/scribe_score.pdf")
plotStepHist(PSMs, targets_01fdr, decoys, :kendall, range(-20, 0, length=100), title = "Kendall Correlation log2(p-val)", label_a = "Targets ≤ 0.1% FDR", label_b = "Decoys", f_out = "/Users/n.t.wamsley/Projects/TEST_DATA/figs/kendall.pdf")
plotStepHist(PSMs, targets_01fdr, decoys, :hyperscore, range(1,100, length=1000), title = "XTandem HyperScore", label_a = "Targets ≤ 0.1% FDR", label_b = "Decoys", f_out = "/Users/n.t.wamsley/Projects/TEST_DATA/figs/hyperscore.pdf")
plotStepHist(PSMs, targets_01fdr, decoys, :rank_total, range(1, 50, length=50), title = "Matched Ions Rank", label_a = "Targets ≤ 0.1% FDR", label_b = "Decoys", f_out = "/Users/n.t.wamsley/Projects/TEST_DATA/figs/matched_ions_rank.pdf")
plotStepHist(PSMs, targets_01fdr, decoys, :rank_hyper, range(1, 50, length=50), title = "Hyperscore Rank", label_a = "Targets ≤ 0.1% FDR", label_b = "Decoys", f_out = "/Users/n.t.wamsley/Projects/TEST_DATA/figs/hyperscore_rank.pdf")
plotStepHist(PSMs, targets_01fdr, decoys, :rank_scribe, range(1, 50, length=50), title = "Scribe Score Rank", label_a = "Targets ≤ 0.1% FDR", label_b = "Decoys", f_out = "/Users/n.t.wamsley/Projects/TEST_DATA/figs/scribe_score_rank.pdf")
plotStepHist(PSMs, targets_01fdr, decoys, :poisson, range(-50, 0, length=100), title = "Poisson", label_a = "Targets ≤ 0.1% FDR", label_b = "Decoys", f_out = "/Users/n.t.wamsley/Projects/TEST_DATA/figs/poisson.pdf")
plotStepHist(PSMs, targets_01fdr, decoys, :RT_error, range(0, 40, length=100), title = "RT Error", label_a = "Targets ≤ 0.1% FDR", label_b = "Decoys", f_out = "/Users/n.t.wamsley/Projects/TEST_DATA/figs/rt_error.pdf")
plotStepHist(PSMs, targets_01fdr, decoys, :city_block,  range(-5, 0, length=1000), title = "City Block Distance", label_a = "Targets ≤ 0.1% FDR", label_b = "Decoys", f_out = "/Users/n.t.wamsley/Projects/TEST_DATA/figs/city_block.pdf")
plotStepHist(PSMs, targets_01fdr, decoys, :total_ions,   range(1, 40, length=40), title = "Total Ions", label_a = "Targets ≤ 0.1% FDR", label_b = "Decoys", f_out = "/Users/n.t.wamsley/Projects/TEST_DATA/figs/total_ions.pdf")
merge_pdfs(readdir("/Users/n.t.wamsley/Projects/TEST_DATA/figs/"; join=true), "/Users/n.t.wamsley/Projects/TEST_DATA/figs/discriminant_scores.pdf")
=#

#=
random forests version. 
function rankPSMs!(PSMs::DataFrame, features::Vector{Symbol}; n_folds::Int = 3, n_trees::Int = 500, n_features::Int = 10, max_depth::Int = 10, fraction::AbstractFloat = 0.1, print_importance::Bool = false)
   
    #[:hyperscore,:total_ions,:intensity_explained,:error,:poisson,:spectral_contrast_all, :spectral_contrast_matched,:RT_error,:scribe_score,:y_ladder,:b_ladder,:RT,:diff_hyper,:median_ions,:n_obs,:diff_scribe,:charge,:city_block,:matched_ratio,:weight,:intensity,:count,:SN]
    X = Matrix(PSMs[:,features])
    X_labels = PSMs[:, :decoy]

    permutation = randperm(size(PSMs)[1])
    fold_size = length(permutation)÷n_folds

    folds = [((n-1)*fold_size + 1):(n*fold_size) for n in range(1, n_folds)]

    PSMs[:,:prob] = zeros(Float64, size(PSMs)[1])
    model = ""
    for test_fold_idx in range(1, n_folds)
        train_fold_idxs = vcat([folds[fold] for fold in range(1, length(folds)) if fold != test_fold_idx]...)
        train_features = X[train_fold_idxs,:]
        train_classes = X_labels[train_fold_idxs,1]
        model = build_forest(train_classes, train_features, n_features, n_trees, fraction, max_depth)
        probs = apply_forest_proba(model, X[folds[test_fold_idx],:],[true, false])
        PSMs[folds[test_fold_idx],:prob] = probs[:,2]
        if print_importance
            println(features[sortperm(split_importance(model))])
        end
    end
    return model
end
=#

using MultiKDE
using Distributions, Random, Plots

using KernelDensity
function KDEmapping(X::Vector{T}, Y::Vector{T}; n::Int = 200, bandwidth::AbstractFloat = 1.0, w = 11) where {T<:AbstractFloat}
    x_grid = LinRange(minimum(X), maximum(X), n)
    y_grid = LinRange(minimum(Y), maximum(Y), n)
    ys = zeros(T, n)
    z = zeros(T, (n, n))
    B = kde((X, Y), bandwidth = (bandwidth, bandwidth)) #Uses Silverman's rule by default
    ik = InterpKDE(B)
    #Get KDE
    for i in eachindex(x_grid), j in eachindex(y_grid)
            z[i, j] = Distributions.pdf(ik, x_grid[i], y_grid[j])
    end

    #Monotonic increasing walk along ridge
    max_j = 1
    for i in eachindex(x_grid)
        j = argmax(@view(z[i,:]))
        if y_grid[j] > y_grid[max_j]
            max_j = j
        end
        ys[i] = y_grid[max_j]
    end
    #w = isodd(n÷5) ? n÷5 : n÷5 + 1
    return LinearInterpolation(x_grid, savitzky_golay(ys, w, 3).y, extrapolation_bc = Line())
end

function unweightedEntropy(X::Vector{Union{Missing, T}}) where {T<:AbstractFloat}
    p = X./sum(X)
    StatsBase.entropy(p)
end

function weightedEntropy(X::Vector{Union{Missing, T}}) where {T<:AbstractFloat}
    p = X./sum(X)
    S = StatsBase.entropy(p)
    if S >=3
        return p, S
    else
        w = 0.25*(1 + S)
        intensity = p.^w
        return intensity, StatsBase.entropy(intensity./sum(intensity))
    end
end

X, Hs, Hst, IDtoROW, weights = SearchRAW(MS_TABLE, prosit_mouse_33NCEcorrected_start1_5ppm_15irt,  frags_mouse_detailed_33NCEcorrected_start1, UInt32(1), rt_map,
                            min_frag_count = 4, 
                            topN = 1000, 
                            fragment_tolerance = fragment_tolerance, 
                            λ = Float32(0), 
                            γ =Float32(0),
                            max_peaks = 10000, 
                            scan_range = (101357, 101357), #101357 #22894
                            precursor_tolerance = 20.0,
                            min_spectral_contrast =  Float32(0.5),
                            min_matched_ratio = Float32(0.45),
                            rt_tol = Float32(20.0),
                            frag_ppm_err = 3.34930002879957
                            )
Hs_mat = Matrix(Hs)
argmax(sum(Hs_mat[X.!=0.0,:].!=0.0, dims = 1)) #8th column. 

#SA = X[Hs_mat[:,8].!=0.0]
entropy_sim = []
for i in range(1, size(Hs_mat)[2])
    A = X
    A = A./sum(A)
    SA = weightedEntropy(allowmissing(A))
    B = Hs_mat[Hs_mat[:,i].!=0.0,i]
    B = B./sum(B)
    SB = weightedEntropy(allowmissing(B))
    A[Hs_mat[:,i].!=0.0] += B
    SAB = weightedEntropy(allowmissing(A))
    push!(entropy_sim, 1 - (2*SAB - SA - SB)/(log(4)))
end

entropy_sim = []
for i in range(1, size(Hs_mat)[2])
    A = X[Hs_mat[:,i].!=0.0]
    A = A./sum(A)
    SA = weightedEntropy(allowmissing(A))
    B = Hs_mat[Hs_mat[:,i].!=0.0,i]
    B = B./sum(B)
    SB = weightedEntropy(allowmissing(B))
    #A[Hs_mat[:,i].!=0.0] += B
    A += B
    SAB = weightedEntropy(allowmissing(A))
    push!(entropy_sim, 1 - (2*SAB - SA - SB)/(log(4)))
end


entropy_sim = []
for i in range(1, size(Hs_mat)[2])
    A = X
    A = A./sum(A)
    SA = weightedEntropy(allowmissing(A))
    B = Hs[Hs[:,i].!=0.0,i]
    B = B./sum(B)
    SB = weightedEntropy(allowmissing(collect(B)))
    A[Hs[:,i].!=0.0] += B
    SAB = weightedEntropy(allowmissing(A))
    push!(entropy_sim, 1 - (2*SAB - SA - SB)/(log(4)))
end

SA = X[Hs_mat[:,8].!=0.0]
SA = X[Hs_mat[:,8].!=0.0]
SB = Hs_mat[:,8].!=0.0
SBA = X
#=
Plots.plot(best_psms[best_psms[:,:q_value].<=0.01,:RT], best_psms[best_psms[:,:q_value].<=0.01,:iRT], seriestype=:scatter)
test_x, test_y= KDEmapping(best_psms[best_psms[:,:q_value].<=0.01,:RT], best_psms[best_psms[:,:q_value].<=0.01,:iRT])
Plots.plot!(test_x, test_y)


logit_test = Distributions.Logistic(0, 2)
logit_sample = rand(logit_test, 10000)

logistic_dist(x, p) = sum([log((exp(-(x_i - p[1])/p[2]))/(p[2]*(1 + exp(-(x_i-p[1])/p[2]))^2)) for x_i in x])


logistic_dist(x, p) =  Distributions.logpdf.(Distributions.Logistic(p[1], max(p[2], 0.01)), x)
p = Float64[0, 2]
prob = OptimizationProblem(logistic_dist, p, logit_sample, lb = [-10.0, 1.0], ub = [10.0, 10.0])
sol = solve(prob, NelderMead())

using OptimizationBBO
prob = OptimizationProblem(rosenbrock, x0, p, lb = [-1.0, -1.0], ub = [1.0, 1.0])


using ForwardDiff
logistic_dist(x, p) =  Distributions.logpdf.(Distributions.Logistic(p[1], max(p[2], 0.01)), x)
p = Float64[0, 2]
f = OptimizationFunction(logistic_dist, Optimization.AutoForwardDiff())
prob = OptimizationProblem(f, p, logit_sample, lb = [-10.0, 1.0], ub = [10.0, 10.0])
sol = solve(prob, BFGS())


frag_ppm_errs = [getPPM(x.theoretical_mz, x.match_mz) for x in all_matches]

mix_guess = MixtureModel([Logistic(0, 3), Uniform(-100, 100)], [0.5, 1 - 0.5])

mix_mle = fit_mle(mix_guess, (frag_ppm_errs); display = :iter, atol = 1e0, robust = true, infos = false)

import Distributions.fit_mle
function fit_mle(a::Logistic{T}, x::Vector{T}, y::Vector{T}; μ::Float64=NaN, θ::Float64=NaN) where T<:Real
    println("mu $μ")
    println("theta $θ")
    println(length(x))
    println(sum(x))
    println(sum(y))
    p = Float64[0, 2]
    logistic_dist(x, p) =  sum([log(Distributions.pdf(Distributions.Logistic(p[1], max(p[2], 0.01)), x[i])*y[i]) for i in 1:length(x)])
    f = OptimizationFunction(logistic_dist, Optimization.AutoForwardDiff())
    prob = OptimizationProblem(f, p, y, lb = [-10.0, 1.0], ub = [10.0, 10.0])
    sol = solve(prob, BFGS())
    return Distributions.Logistic(sol[1], sol[2])
end






a = Distributions.pdf(Distributions.Logistic(0, 2), 2)
=#