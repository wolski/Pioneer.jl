
function getDistanceMetrics(X::Vector{T}, H::SparseMatrixCSC{T, Int64}) where {T<:AbstractFloat}
    scribe_scores = zeros(T, H.n)
    city_block_scores = zeros(T, H.n)
    spectral_contrast_scores = zeros(T, H.n)
    matched_ratio = zeros(T, H.n)

    matched = [x>0 ? 1 : 0 for x in X]

    for col in range(1, H.n)
        H_sqrt_sum = zero(T)
        X_sqrt_sum = zero(T)
        H2_norm = zero(T)
        X2_norm = zero(T)
        dot_product = zero(T)
        scribe_score = zero(T)
        city_block_dist = zero(T)
        matched_sum = zero(T)
        unmatched_sum = zero(T)
    

        N = 0
        @turbo for i in range(H.colptr[col], H.colptr[col + 1]-1)
            H_sqrt_sum += sqrt(H.nzval[i])
            X_sqrt_sum += sqrt(X[H.rowval[i]] + 1e-10)#/Xsum
            H2_norm += H.nzval[i]^2
            X2_norm += X[H.rowval[i]]^2 + 1e-10
            dot_product += H.nzval[i]*X[H.rowval[i]]
            matched_sum += H.nzval[i]*matched[H.rowval[i]]
            unmatched_sum += H.nzval[i]*(1 - matched[H.rowval[i]])
            N += 1
        end

  
        #Sqrt of sum of squares
        H2_norm = sqrt(H2_norm)
        X2_norm = sqrt(X2_norm)

        @turbo for i in range(H.colptr[col], H.colptr[col + 1]-1)
            scribe_score +=  (
                                (sqrt(H.nzval[i])/H_sqrt_sum) - 
                                (sqrt(X[H.rowval[i]])/X_sqrt_sum)
                                )^2  
            city_block_dist += abs(
                (H.nzval[i]/H2_norm) -
                (X[H.rowval[i]]/X2_norm)
            )        
        end

        scribe_scores[col] = -log((scribe_score)/N)
        city_block_scores[col] = -log((city_block_dist)/N)
        spectral_contrast_scores[col] = dot_product/(H2_norm*X2_norm)
        matched_ratio[col] = matched_sum/unmatched_sum
    end

    entropy_scores = getEntropy(X, H)

    return (scribe = scribe_scores, 
            city_block = city_block_scores, 
            spectral_contrast = spectral_contrast_scores, 
            matched_ratio = matched_ratio,
            entropy_sim = entropy_scores)

end
    
function getEntropy(X::Vector{Float32}, H::SparseMatrixCSC{Float32, Int64}) where {T<:AbstractFloat}
    entropy_sim = zeros(T, H.n)
    for col in range(1, H.n)

        Hsum = zero(T)
        Xsum = zero(T)
        HXsum = zero(T)

        Hentropy = zero(T)
        Xentropy = zero(T)
        HXentropy = zero(T)

        @turbo for i in range(H.colptr[col], H.colptr[col + 1]-1)
            hp = H.nzval[i]#/Hsum
            xp = X[H.rowval[i]]#/Xsum
            Hentropy += hp*log(hp)
            #HXentropy += (hp + xp)*log(hp + xp)
            Xentropy += xp*log(xp + 1e-10)
            Xsum += xp
            Hsum += hp
            #HXsum += xp + hp
        end

        @turbo for i in range(H.colptr[col], H.colptr[col + 1]-1)
            hp = H.nzval[i]/Hsum
            xp = X[H.rowval[i]]/Xsum
            HXentropy += (hp + xp)*log(hp + xp)
            HXsum += xp + hp
        end
        Xentropy = log(Xsum) - Xentropy/Xsum
        HXentropy = log(HXsum) - HXentropy/HXsum
        Hentropy = log(Hsum) - Hentropy/Hsum
        
        if (Xentropy < 3) | (Hentropy < 3)

            Xw = Xentropy < 3 ? 0.25*(1 + Xentropy) : 1.0
            Hw = Hentropy < 3 ? 0.25*(1 + Hentropy) :  1.0
            HXw = HXentropy < 3 ? 0.25*(1 + HXentropy) : 1.0

            Hentropy = zero(T)
            Xentropy = zero(T)
            HXentropy = zero(T)
            Hsum = zero(T)
            Xsum = zero(T)
            HXsum = zero(T)
            @turbo for i in range(H.colptr[col], H.colptr[col + 1]-1)
                hp = H.nzval[i]^Hw#/Hsum
                xp = X[H.rowval[i]]^Xw#/Xsum
                Hentropy += hp*log(hp)
                Xentropy += xp*log(xp + 1e-10)
                Xsum += xp
                Hsum += hp
            end

            @turbo for i in range(H.colptr[col], H.colptr[col + 1]-1)
                hp = (H.nzval[i]^Hw)/Hsum
                xp = (X[H.rowval[i]]^Xw)/Xsum
                hxp = (hp + xp)^HXw
                HXentropy += (hxp)*log(hxp)
                HXsum += hxp
            end

            Xentropy = log(Xsum) - Xentropy/Xsum
            HXentropy = log(HXsum) - HXentropy/HXsum 
            Hentropy = log(Hsum) - Hentropy/Hsum
            HXw = HXentropy < 3 ? 0.25*(1 + HXentropy) : 1.0
            HXentropy = zero(Float32)
            HXsum = zero(Float32)
            @turbo for i in range(H.colptr[col], H.colptr[col + 1]-1)
                hp = (H.nzval[i]^Hw)/Hsum
                xp = (X[H.rowval[i]]^Xw)/Xsum
                hxp = (hp + xp)^HXw
                HXentropy += (hxp)*log(hxp)
                HXsum += hxp
            end

            HXentropy = log(HXsum) - HXentropy/HXsum
        end

        entropy_sim[col] = (1 - (2*HXentropy - Xentropy - Hentropy)/(log(4)))
    end
    return entropy_sim
end

@time PSMs = SearchRAW(
    Arrow.Table(MS_TABLE_PATHS[1]), 
    prosit_mouse_33NCEcorrected_start1_5ppm_15irt,  
    frags_mouse_detailed_33NCEcorrected_start1, 
    UInt32(1), #MS_FILE_IDX
    RT_to_iRT_map_dict[1], #RT to iRT map
    min_frag_count = 4, 
    topN = 1000, 
    fragment_tolerance = quantile(frag_err_dist_dict[1], 0.975), 
    λ = Float32(0), 
    γ =Float32(0),
    max_peaks = 10000, 
    #scan_range = (0, length(MS_TABLE[:scanNumber])), #101357 #22894
    scan_range = (0, 300000), #101357 #22894
    precursor_tolerance = 20.0,
    min_spectral_contrast =  Float32(0.5),
    min_matched_ratio = Float32(0.45),
    rt_tol = Float32(20.0),
    frag_ppm_err = frag_err_dist_dict[1].μ
    )


    MS_TABLE = Arrow.Table(MS_TABLE_PATHS[1])    
    best_psms = ""
    ms_file_idx = 1
        best_psms = combine(sdf -> sdf[argmax(sdf.prob),:], groupby(PSMs[1][PSMs[1][:,:q_value].<=0.1,:], :precursor_idx))
   
    transform!(best_psms, AsTable(:) => ByRow(psm -> 
                precursors_mouse_detailed_33NCEcorrected_start1[psm[:precursor_idx]].mz
                ) => :prec_mz
                )
    
    #Need to sort RTs 
    sort!(best_psms,:RT, rev = false)

    #Build RT index of precursors to integrate
    rt_index = buildRTIndex(best_psms)

    println("Integrating MS2...")
    @time ms2_chroms = integrateMS2(MS_TABLE, rt_index, frags_mouse_detailed_33NCEcorrected_start1, 
                    UInt32(ms_file_idx), 
                    fragment_tolerance=quantile(frag_err_dist_dict[ms_file_idx], 0.975), 
                    frag_ppm_err = frag_err_dist_dict[ms_file_idx].μ,
                    λ=zero(Float32),  
                    γ=zero(Float32), 
                    max_peak_width = 2.0, 
                    scan_range = (0, length(MS_TABLE[:scanNumber]))#(101357, 101357)
                    #scan_range = (101357, 111357)
                    );

                    length(unique([getPeakInd(fragmentMatches[i]) for i in range(1, nmatches)]))
    MS_TABLE = Arrow.Table(MS_TABLE_PATHS[1])
    ms_file_idx = 1
    @time rtPSMs, all_matches = SearchRAW(MS_TABLE, 
                    prosit_mouse_33NCEcorrected_start1_5ppm_15irt,  
                    frags_mouse_detailed_33NCEcorrected_start1, 
                    UInt32(ms_file_idx), 
                    x->x, #Mapp RT to iRT
                    min_frag_count = 7, 
                    topN = 5, 
                    fragment_tolerance = init_frag_tol,#20.0, 
                    λ = Float32(0), 
                    γ =Float32(0),
                    max_peaks = 10000, 
                    scan_range = (0, length(MS_TABLE[:scanNumber])), #All Scans
                    precursor_tolerance = 20.0,
                    min_spectral_contrast =  Float32(0.95),
                    min_matched_ratio = Float32(.6),
                    rt_tol = Float32(1e6), #Set arbitrarily high
                    sample_rate = 0.01, #Sampling rate
                    frag_ppm_err = 0.0,
                    collect_frag_errs = true
                    );
                    transform!(rtPSMs, AsTable(:) => ByRow(psm -> Float64(getIRT(precursors_mouse_detailed_33NCEcorrected_start1[psm[:precursor_idx]]))) => :iRT);
                    transform!(rtPSMs, AsTable(:) => ByRow(psm -> Float64(MS_TABLE[:retentionTime][psm[:scan_idx]])) => :RT);
                    transform!(rtPSMs, AsTable(:) => ByRow(psm -> isDecoy(precursors_mouse_detailed_33NCEcorrected_start1[psm[:precursor_idx]])) => :decoy);
                    rtPSMs = rtPSMs[rtPSMs[:,:decoy].==false,:];
                
                    best_precursors = Set(rtPSMs[:,:precursor_idx]);
                    best_matches = [match for match in all_matches if match.prec_id ∈ best_precursors];
                    frag_ppm_errs = [_getPPM(match.theoretical_mz, match.match_mz) for match in best_matches];
                    #Model fragment errors with a mixture model of a uniform and laplace distribution 
                    @time frag_err_dist = estimateErrorDistribution(frag_ppm_errs, Laplace{Float64}, 0.0, 3.0, 30.0);
                
                    RT_to_iRT_map = KDEmapping(rtPSMs[:,:RT], rtPSMs[:,:iRT], n = 50, bandwidth = 5.0);
                    plotRTAlign(rtPSMs[:,:RT], rtPSMs[:,:iRT], RT_to_iRT_map);
                



@showprogress for i in 1:10
    sleep(1)
end

@showprogress pmap(1:10) do i
    sleep(1)
end


@sync @distributed for i in 1:10
    sleep(1)
end
