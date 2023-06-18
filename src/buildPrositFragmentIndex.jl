abstract type FragmentIndexType end 

struct FragmentIon{T<:AbstractFloat}
    frag_mz::T
    pep_id::UInt32
    prec_mz::T
    prec_charge::UInt8
end

getFragMZ(f::FragmentIon) = f.frag_mz
getPepID(f::FragmentIon) = f.pep_id
getPrecMZ(f::FragmentIon) = f.prec_mz
getPrecCharge(f::FragmentIon) = f.prec_charge

#Make sortable by fragment mz. 
import Base.<
import Base.>
<(y::FragmentIon, x::T) where {T<:Real} = getFragMZ(y) < x
<(x::T, y::FragmentIon) where {T<:Real} = <(y, x)
>(y::FragmentIon, x::T) where {T<:Real} = getFragMZ(y) > x
>(x::T, y::FragmentIon) where {T<:Real} = >(y, x)

struct LibraryFragment{T<:AbstractFloat} <: FragmentIndexType
    frag_mz::T
    prec_mz::T
    intensity::Float32
    is_y_ion::Bool
    ion_index::UInt8
    frag_charge::UInt8
    prec_charge::UInt8
    pep_id::UInt32
end

getFragMZ(f::FragmentIndexType) = f.frag_mz
getPepID(f::FragmentIndexType) = f.pep_id
getPrecMZ(f::FragmentIndexType) = f.prec_mz

import Base.<
import Base.>
<(y:: LibraryFragment, x::T) where {T<:Real} = getFragMZ(y) < x
<(x::T, y:: LibraryFragment) where {T<:Real} = <(y, x)
>(y:: LibraryFragment, x::T) where {T<:Real} = getFragMZ(y) > x
>(x::T, y:: LibraryFragment) where {T<:Real} = >(y, x)

getIntensity(f::LibraryFragment) = f.intensity
isyIon(f::LibraryFragment) = f.is_y_ion
getIonIndex(f::LibraryFragment) = f.ion_index
getFragCharge(f::LibraryFragment) = f.frag_charge
getPrecCharge(f::LibraryFragment) = f.prec_charge

function buildFragmentIndex!(frag_ions::Vector{FragmentIon{T}}, bin_ppm::T; max_charge::UInt8 = UInt8(4), min_charge::UInt8 = UInt8(2), low_prec_mz::Float64 = 300.0, high_prec_mz::Float64 = 1100.0) where {T<:AbstractFloat}
   
    #The fragment ions are divided into bins of roughtly equal m/z width.
    #That should correspond to roughly half the fragment mass accuracy of the detector?
    frag_index = FragmentIndex(T) 

    function fillPrecursorBin!(frag_index::FragmentIndex, frag_ions::Vector{FragmentIon{T}}, max_charge::UInt8, min_charge::UInt8, bin::UInt32, start::Int, stop::Int, low_prec_mz::Float64, high_prec_mz::Float64)
        i = 1 #Index of current fragme nt
        for ion_index in range(start, stop)
            pep_id = getPepID(frag_ions[ion_index])
                prec_mz = getPrecMZ(frag_ions[ion_index])#(getPrecMZ(frag_ions[ion_index]) + PROTON*(charge-1))/charge #m/z of the precursor
                if (prec_mz < low_prec_mz/max_charge) | (prec_mz > high_prec_mz*min_charge) #Precursor m/z outside the bounds
                    continue
                end
                #Add precursor corresponding to the charge state
                addPrecursorBinItem!(frag_index,
                                    bin,
                                    #i,
                                    PrecursorBinItem(pep_id, prec_mz, getPrecCharge(frag_ions[ion_index]))
                                    )
                #frag_index.precursor_bins[bin].precs[i] = PrecursorBinItem(getPepID(ion), (getPrecMZ(ion) + PROTON*(charge-1))/charge)
                i += 1 #Move to the next fragment 
        end
    end

    bin = UInt32(1) #Current fragment bin index
    start = 1 #Fragment index of the first fragment in the current bin

    getPPM(frag_mz::T, ppm::T) = ppm*frag_mz/1e6

    diff = getPPM(getFragMZ(frag_ions[start]), bin_ppm) #ppm tolerance of the current fragment bin

    #Build bins 
    for stop in 2:length(frag_ions)
        if getFragMZ(frag_ions[stop]) < 150.0
            start += 1
            continue
        end
        #Ready to make another precursor bin. 
        if (getFragMZ(frag_ions[stop]) - getFragMZ(frag_ions[start])) > diff
            #Nedds to be stop - 1 to gaurantee the smallest and largest fragment
            #in the bin differ by less than diff 
            last_frag_in_bin = stop - 1
            #Add a new fragment bin
            addFragmentBin!(frag_index, 
                            FragBin(getFragMZ(frag_ions[start]),
                                    getFragMZ(frag_ions[last_frag_in_bin]),
                                    bin
                                    )
                            )
            addPrecursorBin!(frag_index, 
                                #Preallocate an empty precursor bin of the correct length 
                                PrecursorBin(Vector{PrecursorBinItem{T}}())#undef, (last_frag_in_bin - start + 1)*length(charges)))
                                )
        
            fillPrecursorBin!(frag_index, frag_ions, max_charge, min_charge, bin, start, last_frag_in_bin, low_prec_mz, high_prec_mz)

            #Sort the precursor bin by precursor m/z
            sort!(getPrecursors(getPrecursorBin(frag_index, bin)), by = x->getPrecMZ(x));

            #Update counters and ppm tolerance 
            bin += UInt32(1)
            start = stop
            diff = getPPM(getFragMZ(frag_ions[start]), bin_ppm)
            if getFragMZ(frag_ions[stop])> 1700.0
                break
            end
        end
    end
    return frag_index
end

mutable struct FragmentMatch{T<:AbstractFloat}
    predicted_intensity::T
    peak_intensity::T
    theoretical_mz::T
    match_mz::T
    peak_ind::Int64
    frag_index::UInt8
    frag_charge::UInt8
    frag_isotope::UInt8
    ion_type::Char
    prec_id::UInt32
    count::UInt8
    scan_idx::UInt32
    ms_file_idx::UInt32
end

FragmentMatch() = FragmentMatch(Float64(0), Float64(0), Float64(0), Float64(0), 0, UInt8(0), UInt8(0), UInt8(0),'y', UInt32(0), UInt8(0), UInt32(0), UInt32(0))
getMZ(f::FragmentMatch) = f.theoretical_mz
getPrecID(f::FragmentMatch) = f.prec_id
getCharge(f::FragmentMatch) = f.frag_charge
getIsotope(f::FragmentMatch) = f.frag_isotope
getIonType(f::FragmentMatch) = f.ion_type
getInd(f::FragmentMatch) =f.frag_index
getPeakInd(f::FragmentMatch) = f.peak_ind
getIntensity(f::FragmentMatch) = f.peak_intensity
getCount(f::FragmentMatch) = f.count
getMSFileID(f::FragmentMatch) = f.ms_file_idx


#mutable struct IonIndexMatch{T<:AbstractFloat}
#    summed_intensity::T
#    count::Int64
#end

#getCount(i::IonIndexMatch{T}) where {T<:AbstractFloat} = i.count


function findFirstFragmentBin(frag_index::Vector{FragBin{T}}, frag_min::T, frag_max::T) where {T<:AbstractFloat}
    #Binary Search
    lo, hi = 1, length(frag_index)
    potential_match = nothing
    while lo <= hi

        mid = (lo + hi) ÷ 2

        if (frag_min) <= getHighMZ(frag_index[mid])
            if (frag_max) >= getHighMZ(frag_index[mid]) #Frag tolerance overlaps the upper boundary of the frag bin
                potential_match = mid
            end
            hi = mid - 1
        elseif (frag_max) >= getLowMZ(frag_index[mid]) #Frag tolerance overlaps the lower boundary of the frag bin
            if (frag_min) <= getLowMZ(frag_index[mid])
                potential_match = mid
                #return mid
            end
            lo = mid + 1
        end
    end

    return potential_match#, Int64(getPrecBinID(frag_index[potential_match]))
end

function searchPrecursorBin!(precs::Dictionary{UInt32, UInt8}, precursor_bin::PrecursorBin{T}, window_mz::Float32, window_min::U, window_max::U) where {T,U<:AbstractFloat}
   
    N = getLength(precursor_bin)

    #if N>1000000
    #    return nothing, nothing
    #end

    lo, hi = 1, N

    while lo <= hi
        mid = (lo + hi) ÷ 2
        if getPrecMZ(getPrecursor(precursor_bin, mid)) < window_min
            lo = mid + 1
        else
            hi = mid - 1
        end
    end

    window_start = (lo <= N ? lo : return nothing, nothing)

    if getPrecMZ(getPrecursor(precursor_bin, window_start)) > window_max
        return nothing, nothing
    end

    lo, hi = window_start, N

    while lo <= hi
        mid = (lo + hi) ÷ 2
        if getPrecMZ(getPrecursor(precursor_bin, mid)) > window_max
            hi = mid - 1
        else
            lo = mid + 1
        end
    end

    window_stop = hi

    function addFragmentMatches!(precs::Dictionary{UInt32, UInt8}, precursor_bin::PrecursorBin{T}, window_min::AbstractFloat, window_max::AbstractFloat, start::Int, stop::Int) where {T<:AbstractFloat}
        for precursor_idx in start:stop
            
            precursor = getPrecursor(precursor_bin, precursor_idx)
            prec_mz = getPrecMZ(precursor)
            prec_id = getPrecID(precursor)
            charge = getPrecCharge(precursor)

            _min = window_min - 3.0*NEUTRON/charge#upper_tol[charge]
            _max = window_max + 1.0*NEUTRON/charge#lower_tol[charge]
            #println("A")
            if (_min <= prec_mz) & (_max >= prec_mz)
                #println("B")
                if haskey(precs, prec_id)
                    precs[prec_id] += UInt8(1)
                else
                    insert!(precs, prec_id, UInt8(1))
                end
            end
        end

    end

    addFragmentMatches!(precs, precursor_bin, window_min, window_max, window_start, window_stop)

    return window_start, window_stop

end

#const upper_tol = [(3.0*NEUTRON), (3.0*NEUTRON)/2, (3.0*NEUTRON)/3, (3.0*NEUTRON)/4]
#const lower_tol = [(1*NEUTRON), (1*NEUTRON)/2, (1*NEUTRON)/3, (1*NEUTRON)/4]

function queryFragment!(precs::Dictionary{UInt32, UInt8}, frag_index::FragmentIndex{T}, min_frag_bin::Int64, frag_min::U, frag_max::U, prec_mz::Float32, prec_tol::U) where {T,U<:AbstractFloat}
    
    frag_bin = findFirstFragmentBin(getFragBins(frag_index), frag_min, frag_max)
    #No fragment bins contain the fragment m/z
    if (frag_bin === nothing)
        return min_frag_bin
    #This frag bin has already been searched
    elseif frag_bin <= min_frag_bin
        return min_frag_bin
    end

    i = 1
    while (frag_bin < length(getFragBins(frag_index))) #getLowMZ(getFragmentBin(frag_index, frag_bin)) <frag_max
        #Fragment bin matches the fragment ion
        #println(i)
        i += 1
        if (getLowMZ(getFragmentBin(frag_index, frag_bin)) > frag_max)
            return frag_bin
        else
            _min = prec_mz - prec_tol - 3.0*NEUTRON
            _max = prec_mz + prec_tol + 1.0*NEUTRON
            A = length(precs)
            searchPrecursorBin!(precs, getPrecursorBin(frag_index, UInt32(frag_bin)), prec_mz, _min, _max)
            #=if (length(precs) - A) > 100
                println("AFTER ", length(precs) - A)
                println("prec_mz", prec_mz)
                println("frag_min", frag_min)
                println("frag_max", frag_max)
            end=#
            frag_bin += 1
        end

    end

    #Only reach this point if frag_bin exceeds length(frag_index)
    return frag_bin - 1
end

function searchScan!(precs::Dictionary{UInt32, UInt8}, f_index::FragmentIndex{T}, massess::Vector{Union{Missing, U}}, intensities::Vector{Union{Missing, U}}, precursor_window::U, ppm::T, width::T; topN::Int = 20, min_frag_count::Int = 3) where {T,U<:AbstractFloat}
    
    getFragTol(mass::U, ppm::T) = mass*(1 - ppm/1e6), mass*(1 + ppm/1e6)

    function filterPrecursorMatches!(precs::Dictionary{UInt32, UInt8}, topN::Int, min_frag_count::Int) where {T<:AbstractFloat}
        #Do not consider peptides wither fewer than 
        match_count = sum(precs)
        prec_count = length(precs)


        filter!(count->(count>=min_frag_count), precs)

        sort!(precs, rev = true)
        #println(precs)
        #Iterator of Peptide ID's for the `topN` scoring peptides
        return Iterators.take(keys(precs), min(topN, length(keys(precs)))), prec_count, match_count
    end

    min_frag_bin = 0

    for (mass, intensity) in zip(massess, intensities)

        mass, intensity = coalesce(mass, 0.0),  coalesce(intensity, 0.0)

        FRAGMIN, FRAGMAX = getFragTol(mass, ppm) 

        min_frag_bin = queryFragment!(precs, f_index, min_frag_bin, FRAGMIN, FRAGMAX, precursor_window, width)
    end 
    #println("PRECS $precs")
    return filterPrecursorMatches!(precs, topN, min_frag_count)
end

function SearchRAW(
                    spectra::Arrow.Table, 
                    #ptable::PrecursorDatabase,
                    frag_index::FragmentIndex{T},
                    fragment_list::Vector{Vector{LibraryFragment{Float64}}},
                    ms_file_idx::UInt32;
                    precursor_tolerance::Float64 = 0.5,
                    fragment_tolerance::Float64 = 20.0,
                    transition_charges::Vector{UInt8} = UInt8[1],
                    transition_isotopes::Vector{UInt8} = UInt8[0],
                    b_start::Int64 = 3,
                    y_start::Int64 = 3,
                    topN::Int64 = 30,
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
    for (i, spectrum) in enumerate(Tables.namedtupleiterator(spectra))
        if spectrum[:msOrder] != 2
            continue
        end
        ms2 += 1
        #if ms2  != 6600
        #    continue
        #end
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
        #=if (ms2 % 200) == 0
            println("Scan # $ms2")
            println("precs ", length([x for x in pep_id_iterator]))
            println(pep_id_iterator)
            println("unique precursors", prec_count)
            println("macth_coutn", match_count)
            println("expected ", match_count/prec_count)
            println("peaks ", length(spectrum[:masses]))
        end=#
        #unscored_PSMs = UnorderedDictionary{UInt32, XTandem{T}}()

        #ScoreFragmentMatches!(unscored_PSMs, fragmentMatches)

        #=Score!(scored_PSMs, unscored_PSMs, 
                length(spectrum[:intensities]), 
                Float64(sum(spectrum[:intensities])), 
                1.0, 
                scan_idx = Int64(i)
                )=#
    end
    println("processed $ms2 scans!")
    return #DataFrame(scored_PSMs)
end

@time PSMs = SearchRAW(MS_TABLE, prosit_index, UInt32(1))

abstract type FragmentIndexType end 



struct LibraryFragment{T<:AbstractFloat} <: FragmentIndexType
    frag_mz::T
    is_y_ion::Bool
    ion_index::UInt8
    frag_charge::UInt8
    intensity::Float32
end

getFragMZ(f::FragmentIndexType) = f.frag_mz
getPepID(f::FragmentIndexType) = f.pep_id
getPrecMZ(f::FragmentIndexType) = f.prec_mz

import Base.<
import Base.>
<(y:: LibraryFragment, x::T) where {T<:Real} = getFragMZ(y) < x
<(x::T, y:: LibraryFragment) where {T<:Real} = <(y, x)
>(y:: LibraryFragment, x::T) where {T<:Real} = getFragMZ(y) > x
>(x::T, y:: LibraryFragment) where {T<:Real} = >(y, x)

getIntensity(f::LibraryFragment) = f.intensity
isyIon(f::LibraryFragment) = f.is_y_ion
getIonIndex(f::LibraryFragment) = f.ion_index
getFragCharge(f::LibraryFragment) = f.frag_charge
getPrecCharge(f::LibraryFragment) = f.prec_charge






"/Users/n.t.wamsley/Desktop/myPrositLib.csv"
function readPrositLib(prosit_lib_path::String)
    frag_list = Vector{FragmentIon{Float64}}()
    frag_detailed = Vector{Vector{LibraryFragment{Float64}}}()

    rows = CSV.Rows(prosit_lib_path, reusebuffer=false, select = [:RelativeIntensity, :FragmentMz, :PrecursorMz, :Stripped, :ModifiedPeptide,:FragmentNumber,:FragmentCharge,:PrecursorCharge,:FragmentType])
    current_peptide = ""
    current_charge = "1"
    prec_id = UInt32(0)

    for (i, row) in enumerate(rows)
        if (row.ModifiedPeptide::PosLenString != current_peptide) | (row.PrecursorCharge::PosLenString != current_charge)
            current_peptide = row.ModifiedPeptide::PosLenString
            current_charge = row.PrecursorCharge::PosLenString
            prec_id += UInt32(1)
            push!(frag_detailed, Vector{LibraryFragment{Float64}}())
        end

        if (i % 1_000_000) == 0
            println(i/1_000_000)
        end

        if parse(UInt8, row.FragmentNumber::PosLenString) < UInt8(3)
            continue
        end

        push!(frag_list, FragmentIon(parse(Float64, row.FragmentMz::PosLenString), 
                                    prec_id, 
                                    parse(Float64, row.PrecursorMz::PosLenString), 
                                    parse(UInt8, row.PrecursorCharge::PosLenString)))

        push!(frag_detailed[prec_id], LibraryFragment(parse(Float64, row.FragmentMz::PosLenString), 
                                                    (row.FragmentType::PosLenString == 'y'),
                                                    parse(UInt8, row.FragmentNumber::PosLenString),
                                                    parse(UInt8, row.FragmentCharge::PosLenString),
                                                    parse(Float32, row.RelativeIntensity::PosLenString),
                                                    )
                                 )
    end
    sort!(frag_list, by = x->getFragMZ(x))
    return frag_list, frag_detailed
end

rows = CSV.Rows("/Users/n.t.wamsley/Desktop/myPrositLib.csv")

@time prosit_list, prosit_dict = readPrositLib("/Users/n.t.wamsley/Desktop/myPrositLib.csv")

@save "/Users/n.t.wamsley/Projects/prosit_list.jld2"  prosit_list 
@save "/Users/n.t.wamsley/Projects/prosit_dict.jld2"  prosit_dict 