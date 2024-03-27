using LightXML, Base64, Polynomials

function DecodeCoefficients(encoded::String)
    return reinterpret(Float64, Base64.base64decode(encoded))
end

struct PolynomialSpline{T<:Real}
    polynomials::Vector{Polynomial{T, :x}}
    knots::Vector{T}
end

function (p::PolynomialSpline)(x)
    idx = searchsortedfirst(p.knots, x)
    #if (idx == 1) | (idx > length(p.knots))
    #    return missing
    #end
    if (idx == 1)
        return p.polynomials[1](p.knots[1])
    end
    if (idx > length(p.knots))
        return p.polynomials[end](p.knots[end])
    end
    return p.polynomials[idx-1](x - p.knots[idx - 1])
end

struct IsotopeSplineModel{T<:Real}
    splines::Vector{Vector{PolynomialSpline{T}}}
end

function (p::IsotopeSplineModel)(S, I, x)
    return p.splines[S::Int64 + 1][I::Int64 + 1](x::Float64)
end


function buildPolynomials(coefficients::Vector{T}, order::I) where {T<:Real, I<:Integer}
    order += 1
    n_knots = length(coefficients)÷order
    polynomials = Vector{Polynomial{T, :x}}()
    for n in range(1, n_knots)
        start = ((n - 1)*order + 1)
        stop = (n)*order
        push!(polynomials, Polynomial(coefficients[start:stop], :x))
    end
    return polynomials
end

function parseIsoXML(iso_xml_path::String)
    #From LightXML.jl
    xdoc = parse_file(iso_xml_path)

    max_S, max_iso = 0, 0
    for model in root(xdoc)["model"]
        #Use only sulfur-specific models
        if (haskey(attributes_dict(model),"S"))
            if parse(Int64, attributes_dict(model)["S"])+1 > max_S
                max_S = parse(Int64, attributes_dict(model)["S"])+1
            end
            if parse(Int64, attributes_dict(model)["isotope"])+1 > max_iso
                max_iso = parse(Int64, attributes_dict(model)["isotope"])+1
            end
        end
    end

    #Pre-allocate splines 
    splines = Vector{Vector{PolynomialSpline{Float64}}}()
    for i in range(1, max_S)
        push!(splines, [])
        for j in range(1, max_iso)
            push!(
                splines[i], 
                PolynomialSpline(
                                buildPolynomials(Float64[0, 0, 0], 3),
                                Float64[0]
                                            )
            )
        end
    end

    #Fill Splines 
    for model in root(xdoc)["model"]
        if (haskey(attributes_dict(model),"S"))
            S = parse(Int64, attributes_dict(model)["S"])
            iso =  parse(Int64, attributes_dict(model)["isotope"]) 
            splines[S+1][iso+1] = PolynomialSpline(
                buildPolynomials(
                collect(DecodeCoefficients(content(model["coefficients"][1]))),
                parse(Int64, attributes_dict(model)["order"]) - 1
                ),
                collect(DecodeCoefficients(content(model["knots"][1])))
            )
        end
    end

    return IsotopeSplineModel(splines)

end

struct isotope{T<:AbstractFloat,I<:Int}
    mass::T
    sulfurs::I
    iso::I
end

import Base.-
function -(a::isotope{T, I}, b::isotope{T, I}) where {T<:Real,I<:Integer}
    return isotope(
        a.mass - b.mass,
        a.sulfurs - b.sulfurs,
        a.iso - b.iso
    )
end

"""
    getFragAbundance(iso_splines::IsotopeSplineModel{Float64}, frag::isotope{T, I}, prec::isotope{T, I}, pset::Tuple{I, I}) where {T<:Real,I<:Integer}

Get the relative intensities of fragment isotopes starting at M+0. Returns `isotopes` where isotopes[1] is M+0, isotopes[2] is M+1, etc. 
Based on Goldfarb et al. 2018 Approximating Isotope Distributions of Biomolecule Fragments 
CS Omega 2018, 3, 9, 11383-11391
Publication Date:September 19, 2018
https://doi.org/10.1021/acsomega.8b01649

### Input

- `iso_splines::IsotopeSplineModel{Float64}` -- Splines from Goldfarb et. al. that return isotope probabilities given the number of sulfurs and average mass 
- `frag::isotope{T, I}` -- The fragment isotope
- `prec::isotope{T, I}` -- The precursor isotope
- `pset::Tuple{I, I}` -- The first and last precursor isotope that was isolated. (1, 3) would indicate the M+1 through M+3 isotopes were isolated and fragmented.

### Output

Returns `isotopes` where isotopes[1] is M+0, isotopes[2] is M+1, etc. Does not normalize to sum to one

### Notes

- See methods from Goldfarb et al. 2018

### Algorithm 

### Examples 

"""
function getFragAbundance(iso_splines::IsotopeSplineModel{Float64}, frag::isotope{T, I}, prec::isotope{T, I}, pset::Tuple{I, I}) where {T<:Real,I<:Integer}
    #Approximating Isotope Distributions of Biomolecule Fragments, Goldfarb et al. 2018 
    min_p, max_p = first(pset), last(pset) #Smallest and largest precursor isotope

    #placeholder for fragment isotope distributions
    #zero to isotopic state of largest precursor 
    isotopes = zeros(Float64, max_p + 1)
    for f in range(0, max_p) #Fragment cannot take an isotopic state grater than that of the largest isolated precursor isotope
        complement_prob = 0.0 #Denominator in 5) from pg. 11389, Goldfarb et al. 2018

        f_i = coalesce(iso_splines(min(frag.sulfurs, 5), f, Float64(frag.mass)), 0.0) #Probability of fragment isotope in state 'f' assuming full precursor distribution 

        for p in range(max(f, min_p), max_p) #Probabilities of complement fragments 
            complement_prob += coalesce(iso_splines(min(prec.sulfurs - frag.sulfurs, 5), p - f, Float64(prec.mass - frag.mass)), 0.0)
        end
        isotopes[f+1] = f_i*complement_prob
    end

    return isotopes#./sum(isotopes)
end

"""
    getFragAbundance!(isotopes::Vector{Float64}, iso_splines::IsotopeSplineModel{Float64}, frag::isotope{T, I}, prec::isotope{T, I}, pset::Tuple{I, I}) where {T<:Real,I<:Integer}

Get the relative intensities of fragment isotopes starting at M+0. Fills `isotopes` in place. isotopes[1] is M+0, isotopes[2] is M+1, etc. 
Based on Goldfarb et al. 2018 Approximating Isotope Distributions of Biomolecule Fragments 
CS Omega 2018, 3, 9, 11383-11391
Publication Date:September 19, 2018
https://doi.org/10.1021/acsomega.8b01649

### Input

- `isotopes::Vector{Float64}`: -- Vector to hold relative abundances of fragment isotopes. 
- `iso_splines::IsotopeSplineModel{Float64}` -- Splines from Goldfarb et. al. that return isotope probabilities given the number of sulfurs and average mass 
- `frag::isotope{T, I}` -- The fragment isotope
- `prec::isotope{T, I}` -- The precursor isotope
- `pset::Tuple{I, I}` -- The first and last precursor isotope that was isolated. (1, 3) would indicate the M+1 through M+3 isotopes were isolated and fragmented.

### Output

Fills `isotopes` in place with the relative abundances of the fragment isotopes. Does not normalize to sum to one!

### Notes

- See methods from Goldfarb et al. 2018

### Algorithm 

### Examples 

"""
function getFragAbundance!(isotopes::Vector{Float64}, 
                            iso_splines::IsotopeSplineModel{Float64}, 
                            frag::isotope{T, I}, 
                            prec::isotope{T, I}, 
                            pset::Tuple{I, I}) where {T<:Real,I<:Integer}
    #Approximating Isotope Distributions of Biomolecule Fragments, Goldfarb et al. 2018 
    min_p, max_p = first(pset), last(pset) #Smallest and largest precursor isotope
    #placeholder for fragment isotope distributions
    #zero to isotopic state of largest precursor 
    for f in range(0, min(length(isotopes)-1, max_p)) #Fragment cannot take an isotopic state grater than that of the largest isolated precursor isotope
        complement_prob = 0.0 #Denominator in 5) from pg. 11389, Goldfarb et al. 2018

        #Splines don't go above five sulfurs
        f_i = coalesce(iso_splines(min(frag.sulfurs, 5), f, Float64(frag.mass)), 0.0) #Probability of fragment isotope in state 'f' assuming full precursor distribution 

        for p in range(max(f, min_p), max_p) #Probabilities of complement fragments 
            #Splines don't go above five sulfurs 
            complement_prob += coalesce(iso_splines(min(prec.sulfurs - frag.sulfurs, 5), 
                                                            p - f, 
                                                            Float64(prec.mass - frag.mass)), 
                                        0.0)
        end
        isotopes[f+1] = f_i*complement_prob
    end

    #return isotopes#isotopes./sum(isotopes)
end

function getFragAbundance!(isotopes::Vector{Float64}, 
                            iso_splines::IsotopeSplineModel{Float64},
                            prec_mz::Float32,
                            prec_sulfur_count::UInt8,
                            prec_charge::UInt8,
                            frag::LibraryFragmentIon{Float32}, 
                            pset::Tuple{I, I}) where {I<:Integer}
    getFragAbundance!(
        isotopes,
        iso_splines,
        isotope(Float64(frag.mz*frag.frag_charge), Int64(frag.sulfur_count), 0),
        isotope(Float64(prec_mz*prec_charge), Int64(prec_sulfur_count), 0),
        pset
        )
end

function getFragIsotopes!(isotopes::Vector{Float64}, 
                            iso_splines::IsotopeSplineModel{Float64}, 
                            prec_mz::Float32,
                            prec_charge::UInt8,
                            prec_sulfur_count::UInt8,
                            frag::LibraryFragmentIon{Float32}, 
                            prec_isotope_set::Tuple{Int64, Int64})
    fill!(isotopes, zero(eltype(isotopes)))

    monoisotopic_intensity = frag.intensity
    if (first(prec_isotope_set) > 0) | (last(prec_isotope_set) < 1) #Only adjust mono-isotopic intensit if isolated precursor isotopes differ from the prosit training data
        
        #Get relative abundances of frag isotopes given the prosit training isotope set 
        getFragAbundance!(isotopes, 
                            iso_splines, 
                            prec_mz,
                            prec_charge,
                            prec_sulfur_count,
                            frag, 
                            getPrositIsotopeSet(iso_splines,                             
                            prec_mz,
                            prec_charge,
                            prec_sulfur_count)
        )
        prosit_mono = first(isotopes)
        fill!(isotopes, zero(eltype(isotopes)))
        getFragAbundance!(isotopes, iso_splines,                             
                            prec_mz,
                            prec_charge,
                            prec_sulfur_count,
                            frag, prec_isotope_set)
        corrected_mono = first(isotopes)
        monoisotopic_intensity = max(Float32(frag.intensity*corrected_mono/prosit_mono), zero(Float32))
    else
        getFragAbundance!(isotopes, iso_splines,  prec_mz,
        prec_charge,
        prec_sulfur_count, frag, prec_isotope_set)
    end

    #Estimate abundances of M+n fragment ions relative to the monoisotope
    for i in reverse(range(1, length(isotopes)))
        isotopes[i] = max(monoisotopic_intensity*isotopes[i]/first(isotopes), zero(Float32))
    end
end



"""
    getPrecursorIsotopeSet(prec_mz::T, prec_charge::U, window::Tuple{T, T})where {T<:Real,U<:Unsigned}

Given the quadrupole isolation window and the precursor mass and charge, calculates which precursor isotopes were isolated

### Input

- `prec_mz::T`: -- Precursor mass-to-charge ratio
- `prec_charge::U` -- Precursor charge state 
- ` window::Tuple{T, T}` -- The lower and upper m/z bounds of the quadrupole isolation window


### Output

A Tuple of two integers. (1, 3) would indicate the M+1 through M+3 isotopes were isolated and fragmented.

### Notes

- See methods from Goldfarb et al. 2018

### Algorithm 

### Examples 

"""
function getPrecursorIsotopeSet(prec_mz::Float32, 
                                prec_charge::UInt8, 
                                min_prec_mz::Float32, 
                                max_prec_mz::Float32)
    first_iso, last_iso = -1, -1
    for iso_count in range(0, 5) #Arbitrary cutoff after 5 
        iso_mz = iso_count*NEUTRON/prec_charge + prec_mz
        if (iso_mz > min_prec_mz) & (iso_mz < max_prec_mz) 
            if first_iso < 0
                first_iso = iso_count
            end
            last_iso = iso_count
        end
    end
    return (first_iso, last_iso)
end

function getPrositIsotopeSet(iso_splines::IsotopeSplineModel{Float64}, 
                                prec_mz::Float32,
                                prec_charge::UInt8,
                                prec_sulfur_count::UInt8
                             ) #where {T,U<:AbstractFloat}
    prec_mass = Float64(prec_mz*prec_charge)
    prec_sulfur_count = in(prec_sulfur_count, 5)
    M0 = iso_splines(prec_sulfur_count,0,prec_mass)
    M1 = iso_splines(prec_sulfur_count,1,prec_mass)
    if M0 > M1
        if prec_charge <= 2
            return (0, 1)
        elseif prec_charge == 3
            return (0, 2)
        else
            return (0, 3)
        end
    else
        if prec_charge <= 2
            return (0, 2)
        elseif prec_charge == 3
            return (0, 3)
        else
            return (0, 4)
        end
    end
end