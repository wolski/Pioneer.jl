using FASTX
using CodecZlib
using Dictionaries
using Dictionaries
using Combinatorics
using Random
using Arrow
using Tables

include("src/precursor.jl")
include("src/parseFASTA.jl")
include("src/PrecursorDatabase.jl")
include("src/applyMods.jl")


peptides_fasta = digestFasta(parseFasta("/Users/n.t.wamsley/Projects/TEST_DATA/proteomes/UP000000589_10090.fasta.gz"), max_length = 30, min_length = 7)
#peptides_fasta = digestFasta(parseFasta(file_path))
test_table = PrecursorTable()
fixed_mods = Vector{NamedTuple{(:p, :r), Tuple{Regex, String}}}()
var_mods = [(p=r"(M)", r="[MOx]")]
buildPrecursorTable!(test_table, peptides_fasta, fixed_mods, var_mods, 2)
const charge_facs = Float32[1, 0.9, 0.85, 0.8, 0.75]

function adjustNCE(NCE::T, default_charge::Integer, peptide_charge::Integer) where {T<:AbstractFloat}
    return NCE*(charge_facs[default_charge]/charge_facs[peptide_charge])
end

function buildPrositCSV(fasta::String, f_out::String; min_length::Int = 8, max_length::Int = 30,
                        min_charge::Int = 2, max_charge::Int = 4,
                        fixed_mods::Vector{NamedTuple{(:p, :r), Tuple{Regex, String}}} = Vector{NamedTuple{(:p, :r), Tuple{Regex, String}}}(), 
                        var_mods::Vector{NamedTuple{(:p, :r), Tuple{Regex, String}}} = [(p=r"(M)", r="[MOx]")],
                        n_var_mods::Int = 2,
                        nce::Float64 = 30.0,
                        default_charge::Int = 3,
                        dynamic_nce::Bool = true)

    test_table = PrecursorTable()
    buildPrecursorTable!(test_table, fasta, min_length = min_length, max_length = max_length,
                        fixed_mods = fixed_mods, var_mods = var_mods, n_var_mods = n_var_mods)
    
    open(f_out, "w") do file
        write(file, "accession_number,modified_sequence,collision_energy,precursor_charge,prot_ids,pep_id,decoy\n")
        for (id, pep) in ProgressBar(pairs(test_table.id_to_pep))
            sequence = replace(getSeq(pep), r"M\[MOx\]"=>"M(ox)")
            sequence = replace(sequence, r"C\[Carb\]"=>"C")
            unmod_sequence = replace(sequence, r"M(ox)"=>"M")
            prot_id = join([prot_id for prot_id in collect(getProtFromPepID(test_table, id))],";")
            accession = join([getName(getProtein(test_table, prot_id)) for prot_id in collect(getProtFromPepID(test_table, id))],";")
            #Check for illegal amino acid characters
            if (occursin("[H", sequence)) | (occursin("U", sequence)) | (occursin("O", sequence)) |  (occursin("X", sequence)) | occursin("Z", getSeq(pep)) | occursin("B", getSeq(pep))
                continue
            end
            #Enforce length constraints
            #There is a bug here because the sequence length includes "M(ox)". 
            #So the maximum length of a methionine oxidized peptide is actually 30 - 4. 
            if (length(unmod_sequence) > 30) | (length(unmod_sequence) < 7)
                continue
            end 
            decoy = isDecoy(pep)
            #if (decoy == false)
            for charge in range(min_charge, max_charge)
                if dynamic_nce
                    NCE = adjustNCE(nce, default_charge, charge)
                    write(file, "$accession,$sequence,$NCE,$charge,$prot_id,$id,$decoy\n")
                else
                    write(file, "$accession,$sequence,$nce,$charge,$prot_id,$id,$decoy\n")
                end
            end
            #end
        end
    end

end

#=open("/Users/n.t.wamsley/Desktop/targets.csv", "w") do file
    write(file, "accession_number,modified_sequence,collision_energy,precursor_charge,prot_ids,pep_id,decoy\n")
    for (id, pep) in ProgressBar(pairs(test_table.id_to_pep))
        sequence = replace(getSeq(pep), r"M\[MOx\]"=>"M(ox)")
        sequence = replace(sequence, r"C\[Carb\]"=>"C")
        prot_id = join([prot_id for prot_id in collect(getProtFromPepID(test_table, id))],";")
        accession = join([getName(getProtein(test_table, prot_id)) for prot_id in collect(getProtFromPepID(test_table, id))],";")
        #Check for illegal amino acid characters
        if (occursin("[H", sequence)) | (occursin("U", sequence)) | (occursin("O", sequence)) |  (occursin("X", sequence)) | occursin("Z", getSeq(pep)) | occursin("B", getSeq(pep))
            continue
        end
        #Enforce length constraints
        if (length(sequence) > 30) | (length(sequence) < 8)
            continue
        end 
        decoy = isDecoy(pep)
        #if (decoy == false)
        for charge in [2, 3, 4]
            NCE = adjustNCE(30.0, 3, charge)
            write(file, "$accession,$sequence,$NCE,$charge,$prot_id,$id,$decoy\n")
        end
        #end
    end
end=#