function selectTransitions!(transitions::Vector{DetailedFrag{Float32}},
                            scan_to_prec_idx::UnitRange{Int64},
                            precursors_passed_scoring::Vector{UInt32},
                            prec_mzs::Arrow.Primitive{Float32, Vector{Float32}},
                            prec_charges::Arrow.Primitive{UInt8, Vector{UInt8}},
                            prec_irts::Arrow.Primitive{Float32, Vector{Float32}},
                            library_fragment_lookup::LibraryFragmentLookup{Float32}, 
                            iRT::Float32, 
                            iRT_tol::Float32, 
                            mz_bounds::Tuple{Float32, Float32};
                            isotope_err_bounds::Tuple{Int64,Int64} = (3, 1),
                            block_size::Int64 = 10000)# where {V,W<:AbstractFloat}

    transition_idx = 0
    for i in scan_to_prec_idx

       
        prec_idx =  precursors_passed_scoring[i]
        prec_charge = prec_charges[prec_idx]
        prec_mz = prec_mzs[prec_idx]
        #Enforce iRT tolerance on precursors
        if abs(prec_irts[prec_idx] - iRT) > iRT_tol
             continue
        end

        #Manage isotope errors. NEUTRON is global constant. 
        mz_low = - first(mz_bounds) - first(isotope_err_bounds)*NEUTRON/prec_charge
        mz_high = last(mz_bounds) + last(isotope_err_bounds)*NEUTRON/prec_charge

        if (prec_mz < mz_low) | (prec_mz > mz_high)
            continue
        end

        for frag_idx in getPrecFragRange(library_fragment_lookup, prec_idx)#fragment_list[getID(counter, i)]
            frag = getFrag(library_fragment_lookup, frag_idx) 
            transition_idx += 1
            transitions[transition_idx] = getFrag(library_fragment_lookup, frag_idx) #fragment_list.frags[frag_idx]
            if transition_idx + 1 > length(transitions)
                append!(transitions, [DetailedFrag{Float32}() for _ in range(1, block_size)])
            end
            #Grow array if exceeds length
        end
    end

    sort!(@view(transitions[1:transition_idx]), 
            by = x->getMZ(x),
            alg=PartialQuickSort(1:transition_idx)
            #alg = TimSort)
    )

    #reset!(counter)

    #return transition_idx, 0#sort!(transitions, by = x->getFragMZ(x))
    return transition_idx, false
end

#Get relevant framgents given a retention time and precursor mass using a retentionTimeIndex object
function selectRTIndexedTransitions!(
                            transitions::Vector{DetailedFrag{Float32}}, 
                            library_fragment_lookup::LibraryFragmentLookup{Float32}, 
                            prec_mzs::AbstractArray{Float32},
                            prec_charges::AbstractArray{UInt8},
                            prec_sulfur_counts::AbstractArray{UInt8},
                            iso_splines::IsotopeSplineModel{Float32},
                            isotopes::Vector{Float32},
                            rt_index::Union{retentionTimeIndex{Float32, Float32}, Missing}, 
                            rt_start_idx::Int64, 
                            rt_stop_idx::Int64,
                            min_prec_mz::Float32,
                            max_prec_mz::Float32,
                            isotope_err_bounds::Tuple{Int64, Int64},
                            block_size::Int64)
    transition_idx = 0
    n = 0
    for rt_bin_idx in range(rt_start_idx, rt_stop_idx) #Add transitions
        precs = rt_index.rt_bins[rt_bin_idx].prec
        start = searchsortedfirst(precs, by = x->last(x), min_prec_mz - first(isotope_err_bounds)*NEUTRON/2) #First precursor in the isolation window
        stop = searchsortedlast(precs, by = x->last(x), max_prec_mz + last(isotope_err_bounds)*NEUTRON/2) #Last precursor in the isolation window
        for i in start:stop #Get transitions for each precursor
            n += 1 #Keep track of number of precursors 
            prec_idx = first(precs[i])
            prec_sulfur_count, prec_charge, prec_mz = prec_sulfur_counts[prec_idx], prec_charges[prec_idx], prec_mzs[prec_idx]
            mz_low = min_prec_mz - first(isotope_err_bounds)*NEUTRON/prec_charge
            mz_high = max_prec_mz + last(isotope_err_bounds)*NEUTRON/prec_charge

            #If precursor m/z (with isotope error) out of qaudrupole isolation bounds 
            (prec_mz < mz_low) | (prec_mz > mz_high) ? continue : nothing

            #Which precursor isotopes where captured in the quadrupole isolation window? 
            #For example, return (0, 3) if M+0 through M+3 isotopes were captured 
            transition_idx = @inline fillTransitionList!(transitions, 
                                                        getPrecFragRange(library_fragment_lookup, prec_idx),
                                                        getFragments(library_fragment_lookup),
                                                        prec_mz,
                                                        prec_charge,
                                                        prec_sulfur_count,
                                                        transition_idx,
                                                        isotopes, 
                                                        iso_splines, 
                                                        min_prec_mz,
                                                        max_prec_mz,
                                                        block_size
                                                        )
        end
    end

    sort!(@view(transitions[1:transition_idx]), 
          by = x->getMZ(x),
          alg=PartialQuickSort(1:transition_idx))

    #return sort!(transitions, by = x->getFragMZ(x)), prec_ids, transition_idx, prec_idx #Sort transitions by their fragment m/z. 
    return transition_idx, n
end

function fillTransitionList!(transitions::Vector{DetailedFrag{Float32}}, 
                            precursor_fragment_range::UnitRange{UInt32},
                            fragment_ions::Vector{DetailedFrag{Float32}},
                            prec_mz::Float32,
                            prec_charge::UInt8,
                            prec_sulfur_count::UInt8,
                            transition_idx::Int64, 
                            isotopes::Vector{Float32}, 
                            iso_splines::IsotopeSplineModel{Float32}, 
                            min_prec_mz::Float32,
                            max_prec_mz::Float32,
                            block_size::Int64)::Int64 #where {T,U,V,W<:AbstractFloat,I<:Integer}

    NEUTRON = Float64(1.00335)
    prec_isotope_set = getPrecursorIsotopeSet(prec_mz, 
                                            prec_charge, 
                                            min_prec_mz, 
                                            max_prec_mz)

    #for frag in fragment_list[getID(counter, i)]
    for frag_idx in precursor_fragment_range#getPrecFragRange(library_fragment_lookup, prec_idx)

        frag = fragment_ions[frag_idx]
        #Estimate isotope abundances 
        getFragIsotopes!(isotopes, 
                        iso_splines, 
                        prec_mz,
                        prec_charge, 
                        prec_sulfur_count,
                        frag, 
                        prec_isotope_set)

        for iso_idx in range(0, length(isotopes) - 1)

            #Skip if missing
            #iszero(isotopes[iso_idx + 1]) ? continue : nothing
                        
            transition_idx += 1
            transitions[transition_idx] = DetailedFrag(
                frag.prec_id,

                Float32(frag.mz + iso_idx*NEUTRON/frag.frag_charge), #Estimated isotopic m/z
                Float16(frag.intensity),#Float16(isotopes[iso_idx + 1]), #Estimated relative abundance 

                frag.is_y_ion,
                iso_idx>0, #Is the fragment an isotope?

                frag.frag_charge,
                frag.ion_position,
                frag.prec_charge,
                frag.rank,
                frag.sulfur_count
            )#::LibraryFragment{T}
            

            #Grow array if exceeds length
            
            if transition_idx >= length(transitions)
                append!(transitions, [LibraryFragment{T}() for _ in range(1, block_size)])
            end
        end
    end
    return transition_idx
end

function selectIsotopes!(isotopes::Vector{Isotope{T}},
                        prec_list::Vector{Tuple{Union{V, Missing}, UInt32}}, 
                        isotope_dict::UnorderedDictionary{UInt32, Vector{Isotope{T}}}, 
                        prec_ids::Vector{UInt32}, 
                        rt::U, 
                        rt_tol::U) where {T,U,V<:AbstractFloat}
    i = 0
    ion_idx = 0
    prec_idx = 0
    rt_start = searchsortedfirst(prec_list, rt - rt_tol, lt=(r,x)->first(r)<x) #First RT bin to search
    rt_stop = searchsortedlast(prec_list, rt + rt_tol, lt=(x, r)->first(r)>x) #Last RT bin to search 
    #return rt_start, rt_stop
    for i in range(rt_start, rt_stop)
        prec_idx += 1
        for iso in isotope_dict[last(prec_list[i])]
            ion_idx += 1
            (ion_idx > length(isotopes)) ?  append!(isotopes, [Isotope{T}() for _ in range(1, block_size)]) : nothing

            isotopes[ion_idx] = iso
            #append!(isotopes, isotope_dict[last(prec_list[i])])
        end
        (prec_idx > length(prec_ids)) ? append!(prec_ids, zeros(UInt32, block_size)) : nothing
        prec_ids[prec_idx] = last(prec_list[i])
    end
    sort!(@view(isotopes[1:ion_idx]), 
        by = x->getMZ(x),
        alg=PartialQuickSort(1:ion_idx))
    return ion_idx, prec_idx#sort(isotopes, by = x->getMZ(x))
end