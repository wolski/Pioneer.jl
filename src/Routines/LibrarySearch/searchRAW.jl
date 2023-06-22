function SearchRAW(
                    spectra::Arrow.Table, 
                    #ptable::PrecursorDatabase,
                    frag_index::FragmentIndex{T},
                    fragment_list::Vector{Vector{LibraryFragment{Float64}}},
                    ms_file_idx::UInt32;
                    precursor_tolerance::Float64 = 4.25,
                    fragment_tolerance::Float64 = 20.0,
                    transition_charges::Vector{UInt8} = UInt8[1],
                    transition_isotopes::Vector{UInt8} = UInt8[0],
                    b_start::Int64 = 3,
                    y_start::Int64 = 3,
                    topN::Int64 = 20,
                    min_frag_count::Int64 = 4,
                    #fragment_match_ppm::U,
                    data_type::Type{T} = Float64
                    ) where {T,U<:Real}

    scored_PSMs = makePSMsDict(XTandem(data_type))
    #scored_PSMs = makePSMsDict(FastXTandem(data_type))
    #precursorList needs to be sorted by precursor MZ. 
    #Iterate through rows (spectra) of the .raw data. 
    #i = 0
    ms2 = 0
    min_intensity = Float32(0.0)
    nmf_times = Float64[]
    fragger_times = Float64[]
    match_times = Float64[]
    build_design_times = Float64[]
    spectral_contrast_times = Float64[]
    score_times = Float64[]
    for (i, spectrum) in enumerate(Tables.namedtupleiterator(spectra))
        if spectrum[:msOrder] != 2
            continue
        end
        ms2 += 1
        if ms2 < 50000
            continue
        elseif ms2 > 51000
            continue
        end
        fragmentMatches = Vector{FragmentMatch{Float32}}()
        precs = Dictionary{UInt32, UInt8}()
        pep_id_iterator, prec_count, match_count = searchScan!(precs, 
                    frag_index, 
                    spectrum[:masses], spectrum[:intensities], spectrum[:precursorMZ], 
                    fragment_tolerance, 
                    precursor_tolerance,
                    min_frag_count = min_frag_count, 
                    topN = topN
                    )

        fragger_time = @elapsed transitions = selectTransitions(fragment_list, pep_id_iterator)
        push!(fragger_times, fragger_time)
        match_time = @elapsed fragmentMatches, fragmentMisses = matchPeaks(transitions, 
                                    spectrum[:masses], 
                                    spectrum[:intensities], 
                                    #δs = params[:δs],
                                    δs = zeros(T, (1,)),#[Float64(0)],
                                    scan_idx = UInt32(i),
                                    ms_file_idx = ms_file_idx,
                                    min_intensity = min_intensity
                                    )
        push!(match_times, match_time)
        #println("matches ", length(fragmentMatches))
        #println("misses ", length(fragmentMisses))
        build_design_time = @elapsed X, H, IDtoROW = buildDesignMatrix(fragmentMatches, fragmentMisses, topN)
        push!(build_design_times, build_design_time)
        #Does this always coincide with there being zero fragmentMatches?
        #Could change to length(fragmentMatches) == 0 ?
        if size(H)[2] == 0
            continue
        end

        #Initialize weights for each precursor template. 
        #Should find a more sophisticated way of doing this. 
        #nmf_time = @elapsed W = reshape([Float32(1000) for x in range(1,size(H)[1])], (1, size(H)[1]))

        #Solve NMF. 
        #=nmf_time += @elapsed weights = NMF.solve!(NMF.GreedyCD{Float32}(maxiter=50, verbose = false, 
                                                    lambda_w = 1e3, 
                                                    tol = 1e-6, #Need a reasonable way to choos lambda?
                                                    update_H = false #Important to keep H constant. 
                                                    ), X, W, H).W[1,:]=#

        #=nmf_time += @elapsed weights = NMF.solve!(NMF.ProjectedALS{Float32}(maxiter=50, verbose = false, 
                                                    lambda_w = 1e3, 
                                                    tol = 1e-6, #Need a reasonable way to choos lambda?
                                                    update_H = false #Important to keep H constant. 
                                                    ), X, W, H).W[1,:]=#

        nmf_time = @elapsed weights = coef(fit(LassoModel, H, X[1,:]))
        push!(nmf_times, nmf_time)
        sc_time = @elapsed spectral_contrast = getSpectralContrast(H, X)
        push!(spectral_contrast_times, sc_time)

        #For progress and debugging. 
        if (ms2 % 1000) == 0
            println("ms2: $ms2")
            if ms2 == 8000
                #test_frags = transitions
                #test_matches = fragmentMatches
                #test_misses = fragmentMisses
            end
        end

        unscored_PSMs = UnorderedDictionary{UInt32, XTandem{T}}()

        score = @elapsed ScoreFragmentMatches!(unscored_PSMs, fragmentMatches)

        score += @elapsed Score!(scored_PSMs, unscored_PSMs, 
                length(spectrum[:intensities]), 
                Float64(sum(spectrum[:intensities])), 
                match_count/prec_count, spectral_contrast, weights, IDtoROW,
                scan_idx = Int64(i)
                )
        push!(score_times, score)
    end
    println("processed $ms2 scans!")
    println("mean build: ", mean(build_design_times))
    println("mean fragger: ", mean(fragger_times))
    println("mean matches: ", mean(match_times))
    println("mean nmf: ", mean(nmf_times))
    println("mean s_contrast: ", mean(spectral_contrast_times))
    println("mean score: ", mean(score_times))
    return DataFrame(scored_PSMs)# test_frags, test_matches, test_misses#DataFrame(scored_PSMs)
end
