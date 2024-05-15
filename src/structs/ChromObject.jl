struct ChromObject
    rt::Float16
    intensity::Float32
    scan_idx::UInt32
    precursor_idx::UInt32
end

function growChromObjects!(chromatograms::Vector{ChromObject}, block_size::Int64)
    chromatograms = append!(chromatograms, Vector{ChromObject}(undef, block_size))
end

