abstract type UnscoredPSM{T<:AbstractFloat} <: PSM end

struct SimpleUnscoredPSM{T<:AbstractFloat} <: UnscoredPSM{T}
    best_rank::UInt8 #Highest ranking predicted framgent that was observed
    topn::UInt8 #How many of the topN predicted fragments were observed. 
    b_count::UInt8
    y_count::UInt8
    intensity::T
    error::T
    precursor_idx::UInt32
end

SimpleUnscoredPSM{Float32}() = SimpleUnscoredPSM(UInt8(255), zero(UInt8), zero(UInt8), zero(UInt8), zero(Float32), zero(Float32), UInt32(0))
#LXTandem(::Type{Float64}) = LXTandem(UInt8(255), zero(UInt8), zero(UInt8), zero(UInt8), zero(UInt8), zero(UInt8), Float64(0), zero(UInt8), Float64(0), Float64(0), UInt32(0), UInt32(0))
#SimpleUnscoredPSM() = SimpleUnscoredPSM(Float32)

struct ComplexUnscoredPSM{T<:AbstractFloat} <: UnscoredPSM{T}
    best_rank::UInt8 #Highest ranking predicted framgent that was observed
    topn::UInt8 #How many of the topN predicted fragments were observed. 
    longest_y::UInt8
    longest_b::UInt8
    isotope_count::UInt8
    b_count::UInt8
    b_int::T
    y_count::UInt8
    y_int::T
    error::T
    precursor_idx::UInt32
    ms_file_idx::UInt32
end

ComplexUnscoredPSM{Float32}() = ComplexUnscoredPSM(UInt8(255), zero(UInt8), zero(UInt8), zero(UInt8), zero(UInt8), zero(UInt8), Float32(0), zero(UInt8), Float32(0), Float32(0), UInt32(0), UInt32(0))


function ScoreFragmentMatches!(results::Vector{P}, 
                                IDtoCOL::ArrayDict{UInt32, UInt16}, 
                                matches::Vector{FragmentMatch{Float32}}, 
                                nmatches::Int64, 
                                errdist::Laplace{Float64},
                                 m_rank::Int64) where {P<:UnscoredPSM}
    for i in range(1, nmatches)
        match = matches[i]
        col = IDtoCOL.vals[getPrecID(match)]
        results[col] = ModifyFeatures!(results[col], match, errdist, m_rank)
    end
end

function ModifyFeatures!(score::SimpleUnscoredPSM{T}, match::FragmentMatch{T}, errdist::Laplace{Float64}, m_rank::Int64) where {T<:Real}
    
    best_rank = score.best_rank
    topn = score.topn
    b_count = score.b_count
    y_count = score.y_count
    intensity = score.intensity
    error = score.error
    precursor_idx = score.precursor_idx

    if getIonType(match) == 'b'
        b_count += 1
    else getIonType(match) == 'y'
        y_count += 1
    end

    intensity += getIntensity(match)

    ppm_err = (getMZ(match) - getMatchMZ(match))/(getMZ(match)/1e6)
    #error +=  Distributions.logpdf(errdist, ppm_err*sqrt(getIntensity(match)))
    error +=  Distributions.logpdf(errdist, ppm_err)

    precursor_idx = getPrecID(match)

    if match.predicted_rank < best_rank
        best_rank = match.predicted_rank
    end

    if match.predicted_rank <= m_rank
        topn += one(UInt8)
    end

    return SimpleUnscoredPSM{T}(
        best_rank,
        topn,
        b_count,
        y_count, 
        intensity,
        error,
        precursor_idx
    )
end

function ModifyFeatures!(score::ComplexUnscoredPSM{T}, match::FragmentMatch{T}, errdist::Laplace{Float64}, m_rank::Int64) where {T<:Real}
    
    best_rank = score.best_rank
    topn = score.topn
    longest_y = score.longest_y
    longest_b = score.longest_b
    isotope_count = score.isotope_count
    b_count = score.b_count
    b_int = score.b_int
    y_count = score.y_count
    y_int = score.y_int
    error = score.error
    precursor_idx = score.precursor_idx

    if isIsotope(match)
        #score.isotope_count += 1
        isotope_count += 1
        #score.precursor_idx = getPrecID(match)
        precursor_idx = getPrecID(match)
        #return 
    elseif getIonType(match) == 'b'
        #score.b_count += 1
        #score.b_int += getIntensity(match)
        b_count += 1
        b_int += getIntensity(match)
        if getFragInd(match) > longest_b
            longest_b = getFragInd(match)
        end
    elseif getIonType(match) == 'y'
        y_count += 1
        y_int +=  getIntensity(match)
        if getFragInd(match) > longest_y
            longest_y = getFragInd(match)
        end
    end

    ppm_err = (getFragMZ(match) - getMatchMZ(match))/(getFragMZ(match)/1e6)
    #error +=  Distributions.logpdf(errdist, ppm_err*sqrt(getIntensity(match)))
    error +=  Distributions.logpdf(errdist, ppm_err)

    precursor_idx = getPrecID(match)

    if match.predicted_rank < best_rank
        best_rank = match.predicted_rank
    end

    if match.predicted_rank <= m_rank
        topn += one(UInt8)
    end
    return ComplexUnscoredPSM{T}(
        best_rank,
        min(topn, 255),
        longest_y,
        longest_b,
        min(isotope_count, 255),
        min(b_count,255),
        b_int,
        min(y_count,255),
        y_int,
        error,
        precursor_idx,
        score.ms_file_idx)
end
using SpecialFunctions
