
##########
#Import Libraries
##########
#Data Parsing/Printing
using ArgParse
using CSV, Arrow, Tables, DataFrames, JSON, JLD2, ProgressBars
using Plots
#DataStructures 
using DataStructures, Dictionaries, Distributions, Combinatorics, StatsBase, LinearAlgebra, Random, LoopVectorization, SparseArrays
#Algorithms 
using Interpolations, XGBoost, SavitzkyGolay, NumericalIntegration, ExpectationMaximization
##########
#Import files
##########
##########
#Load Dependencies 
##########

#Fragment Library Parsing
[include(joinpath(pwd(), "src", jl_file)) for jl_file in ["IonType.jl"]]

[include(joinpath(pwd(), "src", "Routines","ParseProsit", jl_file)) for jl_file in ["buildPrositCSV.jl",
                                                                                    "parsePrositLib.jl"]]  

#Generic files in src directory
[include(joinpath(pwd(), "src", jl_file)) for jl_file in ["precursor.jl","isotopes.jl"]]

#ML/Math Routines                                                                                    
[include(joinpath(pwd(), "src","ML", jl_file)) for jl_file in ["sparseNNLS.jl",
                                                                                            "percolatorSortOf.jl",
                                                                                            "kdeRTAlignment.jl",
                                                                                            "entropySimilarity.jl"]]


#Utilities
[include(joinpath(pwd(), "src", "Utils", jl_file)) for jl_file in ["counter.jl",
                                                                    "massErrorEstimation.jl"]]  

#Files needed for PRM routines
[include(joinpath(pwd(), "src", "Routines","LibrarySearch", jl_file)) for jl_file in ["buildFragmentIndex.jl",
                                                                                    "matchpeaksLib.jl",
                                                                                    "buildDesignMatrix.jl",
                                                                                    "spectralDistanceMetrics.jl",
                                                                                    "refinePSMs.jl",
                                                                                    "buildRTIndex.jl",
                                                                                    "searchRAW.jl",
                                                                                    "selectTransitions.jl",
                                                                                   # "integrateMS1.jl",
                                                                                   # "integrateMS2.jl",
                                                                                    "queryFragmentIndex.jl",
                                                                                    ]]


                                                                                                                                 
#Files needed for PSM scoring
[include(joinpath(pwd(), "src", "PSM_TYPES", jl_file)) for jl_file in ["PSM.jl","LibraryXTandem.jl"]]

[include(joinpath(pwd(), "src", "Routines", "PRM","IS-PRM",jl_file)) for jl_file in ["getScanPairs.jl"]]

##########
#Load Spectral Library
#Need to find a way to speed this up.  
@time begin
    @load "/Users/n.t.wamsley/Projects/PROSIT/mouse_080123/frags_mouse_detailed_33NCEcorrected_start1.jld2" frags_mouse_detailed_33NCEcorrected_start1
    @load "/Users/n.t.wamsley/Projects/PROSIT/mouse_080123/precursors_mouse_detailed_33NCEcorrected_start1.jld2" precursors_mouse_detailed_33NCEcorrected_start1
    @load "/Users/n.t.wamsley/Projects/PROSIT/mouse_080123/prosit_mouse_33NCEcorrected_start1_5ppm_15irt.jld2" prosit_mouse_33NCEcorrected_start1_5ppm_15irt
end

###########
#Load RAW File
MS_TABLE_PATHS = ["/Users/n.t.wamsley/RIS_temp/MOUSE_DIA/ThermoRawFileToParquetConverter-main/parquet_out/MA5171_MOC1_DMSO_R01_PZ_DIA.arrow",
"/Users/n.t.wamsley/RIS_temp/MOUSE_DIA/ThermoRawFileToParquetConverter-main/parquet_out/MA5171_MOC1_DMSO_R01_PZ_DIA_duplicate.arrow",
"/Users/n.t.wamsley/RIS_temp/MOUSE_DIA/ThermoRawFileToParquetConverter-main/parquet_out/MA5171_MOC1_DMSO_R01_PZ_DIA_duplicate_2.arrow",
"/Users/n.t.wamsley/RIS_temp/MOUSE_DIA/ThermoRawFileToParquetConverter-main/parquet_out/MA5171_MOC1_DMSO_R01_PZ_DIA_duplicate_3.arrow"]

##########
#Set Search parameters
first_search_params = Dict(
    :collect_frag_errs => true,
    :expected_matches => 1000000,
    :frag_ppm_err => 0.0,
    :fragment_tolerance => 30.0,
    :max_iter => 1000,
    :max_peaks => false,
    :min_frag_count => 7,
    :min_matched_ratio => Float32(0.6),
    :min_spectral_contrast => Float32(0.95),
    :nmf_tol => Float32(100),
    :precursor_tolerance => 5.0,
    :quadrupole_isolation_width => 8.5,
    :regularize => false,
    :rt_bounds => (0.0, 200.0),
    :rt_tol => 200.0,
    :sample_rate => 0.01,
    :topN => 5,
    :λ => zero(Float32),
    :γ => zero(Float32)
)

main_search_params = Dict(
    :expected_matches => 1000000,
    :frag_tol_quantile => 0.975,
    :max_iter => 1000,
    :max_peaks => false,
    :min_frag_count => 4,
    :min_matched_ratio => Float32(0.45),
    :min_spectral_contrast => Float32(0.5),
    :nmf_tol => Float32(100),
    :precursor_tolerance => 5.0,
    :quadrupole_isolation_width => 8.5,
    :regularize => false,
    :rt_bounds =>(-20.0, 200.0),
    :rt_tol => 20.0,
    :topN => 1000,
    :λ => zero(Float32),
    :γ => zero(Float32)
)

integrate_ms2_params = Dict(
    :expected_matches => 1000000,
    :frag_tol_quantile => 0.975,
    :max_iter => 1000,
    :max_peak_width => 2.0,
    :max_peaks => false,
    :min_frag_count => 4,
    :min_matched_ratio => Float32(0.45),
    :min_spectral_contrast => Float32(0.5),
    :nmf_tol => Float32(100),
    :precursor_tolerance => 5.0,
    :quadrupole_isolation_width => 8.5,
    :regularize => false,
    :rt_bounds => (0.0, 200.0),
    :rt_tol => 20.0,
    :sample_rate => 1.0,
    :topN => 1000,
    :λ => zero(Float32),
    :γ => zero(Float32)
)
integrate_ms1_params = Dict(
        :expected_matches => 1000000,
        :frag_tol_quantile => 0.975,
        :max_iter => 1000,
        :max_peak_width => 2.0,
        :max_peaks => false,
        :min_frag_count => 4,
        :min_matched_ratio => Float32(0.45),
        :min_spectral_contrast => Float32(0.5),
        :nmf_tol => Float32(100),
        :precursor_tolerance => 5.0,
        :quadrupole_isolation_width => 8.5,
        :regularize => false,
        :rt_tol => 20.0,
        :rt_bounds => (0.0, 200.0),
        :sample_rate => 1.0,
        :topN => 100,
        :λ => zero(Float32),
        :γ => zero(Float32)
)

###########
#Pre-Search
#Need to Estimate the following from a random sample of high-confidence targets
#1) Fragment Mass error/correction
#2) Fragment Mass tolerance
#3) iRT to RT conversion spline
###########
println("Starting Pre Search...")
@time begin
init_frag_tol = 30.0 #Initial tolerance should probably be pre-determined for each different instrument and resolution. 
RT_to_iRT_map_dict = Dict{Int64, Any}()
frag_err_dist_dict = Dict{Int64,Laplace{Float64}}()
lk = ReentrantLock()
Threads.@threads for (ms_file_idx, MS_TABLE_PATH) in ProgressBar(collect(enumerate(MS_TABLE_PATHS[1:1])))
    MS_TABLE = Arrow.Table(MS_TABLE_PATH)
    println("TEST")
    @time rtPSMs, all_matches =  firstSearch(
                                        MS_TABLE,
                                        prosit_mouse_33NCEcorrected_start1_5ppm_15irt,  
                                        frags_mouse_detailed_33NCEcorrected_start1, 
                                        x->x, #RT to iRT map'
                                        UInt32(ms_file_idx), #MS_FILE_IDX
                                        Laplace(zero(Float64), 10.0),
                                        first_search_params,
                                        scan_range = (0, length(MS_TABLE[:masses]))
                                        );


    function _getPPM(a::T, b::T) where {T<:AbstractFloat}
        (a-b)/(a/1e6)
    end

    transform!(rtPSMs, AsTable(:) => ByRow(psm -> Float64(getIRT(precursors_mouse_detailed_33NCEcorrected_start1[psm[:precursor_idx]]))) => :iRT);
    transform!(rtPSMs, AsTable(:) => ByRow(psm -> Float64(MS_TABLE[:retentionTime][psm[:scan_idx]])) => :RT);
    transform!(rtPSMs, AsTable(:) => ByRow(psm -> isDecoy(precursors_mouse_detailed_33NCEcorrected_start1[psm[:precursor_idx]])) => :decoy);
    rtPSMs = rtPSMs[rtPSMs[:,:decoy].==false,:];

    best_precursors = Set(rtPSMs[:,:precursor_idx]);
    best_matches = [match for match in all_matches if match.prec_id ∈ best_precursors];
    frag_ppm_errs = [_getPPM(match.theoretical_mz, match.match_mz) for match in best_matches];
    #Model fragment errors with a mixture model of a uniform and laplace distribution 
    @time frag_err_dist = estimateErrorDistribution(frag_ppm_errs, Laplace{Float64}, 0.0, 3.0, 30.0);

    RT_to_iRT_map = KDEmapping(rtPSMs[:,:RT], rtPSMs[:,:iRT], n = 50, bandwidth = 2.0);
    plotRTAlign(rtPSMs[:,:RT], rtPSMs[:,:iRT], RT_to_iRT_map);

    lock(lk) do 
        RT_to_iRT_map_dict[ms_file_idx] = RT_to_iRT_map
        frag_err_dist_dict[ms_file_idx] = frag_err_dist
    end
end
end
###########
#Main PSM Search
###########
PSMs_dict = Dict{Int64, DataFrame}()
@time Threads.@threads for (ms_file_idx, MS_TABLE_PATH) in ProgressBar(collect(enumerate(MS_TABLE_PATHS[1:1])))
        MS_TABLE = Arrow.Table(MS_TABLE_PATH)    
        @profview PSMs = mainLibrarySearch(
                                                MS_TABLE,
                                                prosit_mouse_33NCEcorrected_start1_5ppm_15irt,  
                                                frags_mouse_detailed_33NCEcorrected_start1, 
                                                RT_to_iRT_map_dict[ms_file_idx], #RT to iRT map'
                                                UInt32(1), #MS_FILE_IDX
                                                frag_err_dist_dict[ms_file_idx],
                                                main_search_params,
                                                scan_range = (101357, 111357),
                                                #scan_range = (0, length(MS_TABLE[:masses]))
                                            );
        PSMs = PSMs[PSMs[:,:weight].>100.0,:];
        @time refinePSMs!(PSMs, MS_TABLE, precursors_mouse_detailed_33NCEcorrected_start1);
        lock(lk) do 
            PSMs_dict[ms_file_idx] = PSMs
        end
        #println("TEST length(prec_counts) ", length(prec_counts))
end
############
@time PSMs = vcat(values(PSMs_dict)...)
###########
#Clean features
############
PSMs[isnan.(PSMs[:,:matched_ratio]),:matched_ratio] .= Inf
PSMs[(PSMs[:,:matched_ratio]).==Inf,:matched_ratio] .= maximum(PSMs[(PSMs[:,:matched_ratio]).!=Inf,:matched_ratio])
replace!(PSMs[:,:city_block], -Inf => minimum(PSMs[PSMs[:,:city_block].!=-Inf,:city_block]))
replace!(PSMs[:,:scribe_score], Inf => minimum(PSMs[PSMs[:,:scribe_score].!=Inf,:scribe_score]))
#PSMs = DataFrame(CSV.File("/Users/n.t.wamsley/Desktop/PSMs_080423.csv"))
transform!(PSMs, AsTable(:) => ByRow(psm -> length(collect(eachmatch(r"ox", psm[:sequence])))) => [:Mox]);

############
#Target-Decoy discrimination
############

features = [:hyperscore,:total_ions,:intensity_explained,:error,
            :poisson,:spectral_contrast,:entropy_sim,
            :RT_error,:scribe_score,:y_ladder,:RT,:n_obs,:charge,
            :city_block,:matched_ratio,:weight,:missed_cleavage,:Mox,:best_rank,:topn]



@time rankPSMs!(PSMs, features, 
                colsample_bytree = 1.0, 
                min_child_weight = 10, 
                gamma = 10, 
                #subsample = 0.25, 
                subsample = 0.5,
                n_folds = 2,
                num_round = 200, 
                eta = 0.0375, 
                max_depth = 5,
                max_train_size = size(PSMs)[1])

@time getQvalues!(PSMs, PSMs[:,:prob], PSMs[:,:decoy]);
println("Target PSMs at 1% FDR: ", sum((PSMs[:,:q_value].<=0.01).&(PSMs[:,:decoy].==false)))

##########
#Regroup PSMs by file id 
PSMs = groupby(PSMs,:ms_file_idx)

#PSMs[(PSMs[:,:q_value].<=0.01).&(PSMs[:,:decoy].==false),:precursor_idx]
#########
#save psms
#########
#CSV.write("/Users/n.t.wamsley/Projects/TEST_DATA/PSMs_071423.csv", PSMs)
###########
#Integrate 
#best_psms_old = DataFrame(CSV.File("/Users/n.t.wamsley/Desktop/best_psms_080423.csv"))
best_psms_dict = Dict{Int64, DataFrame}()
@time begin
Threads.@threads for (ms_file_idx, MS_TABLE_PATH) in ProgressBar(collect(enumerate(MS_TABLE_PATHS[1:1])))

    MS_TABLE = Arrow.Table(MS_TABLE_PATH)    
    best_psms = ""
    
    best_psms = combine(sdf -> sdf[argmax(sdf.prob),:], groupby(PSMs[ms_file_idx][PSMs[ms_file_idx][:,:q_value].<=0.1,:], :precursor_idx))
   
    transform!(best_psms, AsTable(:) => ByRow(psm -> 
                precursors_mouse_detailed_33NCEcorrected_start1[psm[:precursor_idx]].mz
                ) => :prec_mz
                )
    
    #Need to sort RTs 
    sort!(best_psms,:RT, rev = false)
    #Build RT index of precursors to integrate
    rt_index = buildRTIndex(best_psms)

    println("Integrating MS2...")
    @time ms2_chroms = integrateMS2(MS_TABLE, 
                                    frags_mouse_detailed_33NCEcorrected_start1, 
                                    rt_index,
                                    UInt32(ms_file_idx), 
                                    frag_err_dist_dict[ms_file_idx],
                                    integrate_ms2_params, 
                                    scan_range = (0, length(MS_TABLE[:scanNumber]))
                                    #scan_range = (101357, 102357)
                                    );
    
    #Integrate MS2 Chromatograms 
    transform!(best_psms, AsTable(:) => ByRow(psm -> integratePrecursor(ms2_chroms, UInt32(psm[:precursor_idx]), isplot = false)) => [:intensity, :count, :SN, :slope, :peak_error,:apex,:fwhm]);
    
    #Remove Peaks with 0 MS2 intensity or fewer than 6 points accross the peak. 
    best_psms = best_psms[(best_psms[:,:intensity].>0).&(best_psms[:,:count].>=6),:];
    best_psms[:,:RT_error] = abs.(best_psms[:,:apex] .- best_psms[:,:RT_pred]);

    #Get Predicted Isotope Distributions 
    #For some reason this requires a threadlock. Need to investiage further. 
    isotopes = UnorderedDictionary{UInt32, Vector{Isotope{Float32}}}()
    lock(lk) do 
        isotopes = getIsotopes(best_psms[:,:sequence], best_psms[:,:precursor_idx], best_psms[:,:charge], QRoots(4), 4);
    end

    println(length(keys(isotopes)))
    prec_rt_table = sort(collect(zip(best_psms[:,:RT], UInt32.(best_psms[:,:precursor_idx]))), by = x->first(x));

    println("Integrating MS1...")
    @time ms1_chroms = integrateMS1(MS_TABLE, 
                                    isotopes, 
                                    prec_rt_table, 
                                    UInt32(ms_file_idx), 
                                    frag_err_dist_dict[ms_file_idx], 
                                    integrate_ms1_params,
                                    scan_range = (0, length(MS_TABLE[:scanNumber])))

    #Get MS1/MS2 Chromatogram Correlations and Offsets 
    transform!(best_psms, AsTable(:) => ByRow(psm -> getCrossCorr(ms1_chroms, ms2_chroms, UInt32(psm[:precursor_idx]))) => [:offset,:cross_cor]);

    #Integrate MS1 Chromatograms 
    transform!(best_psms, AsTable(:) => ByRow(psm -> integratePrecursor(ms1_chroms, UInt32(psm[:precursor_idx]), isplot = false)) => [:intensity_ms1, 
    :count_ms1, :SN_ms1, :slope_ms1, :peak_error_ms1,:apex_ms1,:fwhm_ms1]);
    
    lock(lk) do 
        best_psms_dict[ms_file_idx] = best_psms
    end

end
end
#best_psms[(best_psms[:,:q_value].<=0.01) .& (best_psms[:,:decoy].==false),[:precursor_idx,:q_value,:matched_ratio,:entropy_sim,:intensity]]
@time best_psms = vcat(values(best_psms_dict)...)
#Model Features 
features = [:hyperscore,:total_ions,:intensity_explained,:error,:poisson,:spectral_contrast,:RT_error,:y_ladder,:RT,:entropy_sim,:n_obs,:charge,:city_block,:matched_ratio,:scribe_score, :missed_cleavage,:Mox,:best_rank,:topn]
append!(features, [:intensity,:intensity_ms1,:count, :SN, :peak_error,:fwhm,:offset,:cross_cor])

#Train Model 
@time bst = rankPSMs!(best_psms, 
                        features,
                        colsample_bytree = 1.0, 
                        min_child_weight = 10, 
                        gamma = 10, 
                        subsample = 0.5, 
                        n_folds = 5, 
                        num_round = 200, 
                        max_depth = 10, 
                        eta = 0.0375, 
                        max_train_size = size(best_psms)[1])
@time getQvalues!(best_psms, best_psms[:,:prob], best_psms[:,:decoy]);


println("Number of unique Precursors ", length(unique(best_psms[(best_psms[:,:q_value].<=0.01).&(best_psms[:,:decoy].==false),:precursor_idx])))


best_psms[(best_psms[:,:q_value].<=0.01).&(best_psms[:,:decoy].==false),:total_ions]



plot(ms2_chroms[(precursor_idx=precursor_idx,)][:,:rt], ms2_chroms[(precursor_idx=precursor_idx,)][:,:weight], seriestype=:scatter)
best_psms[(best_psms[:,:q_value].<=0.01) .& (best_psms[:,:decoy].==false),[:precursor_idx,:q_value,:matched_ratio,:entropy_sim,:intensity,:RT,:total_ions]][10000:10005,:]
plot(ms2_chroms[(precursor_idx= 2895649,)][:,:rt], ms2_chroms[(precursor_idx= 2895649,)][:,:weight], seriestype=:scatter)
plot(ms2_chroms[(precursor_idx=7473645,)][:,:rt], ms2_chroms[(precursor_idx= 7473645,)][:,:weight], seriestype=:scatter)
plot(ms2_chroms[(precursor_idx= 7203709,)][:,:rt], ms2_chroms[(precursor_idx=  7203709,)][:,:weight], seriestype=:scatter)
plot(ms2_chroms[(precursor_idx=  6336168,)][:,:rt], ms2_chroms[(precursor_idx=   6336168,)][:,:weight], seriestype=:scatter)
#Why not found in ms2_chroms?

