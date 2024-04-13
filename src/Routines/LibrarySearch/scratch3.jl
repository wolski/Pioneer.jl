abstract type Node end
getVal(nd::Node) = nd.val
getBinID(nd::Node) = nd.bin_id
getTopID(nd::Node) = nd.top_id
getLastID(nd::Node) = nd.last_id

struct TTreeNode{I<:Unsigned,T<:Real} <: Node
    val::T
    bin_id::I
    top_id::I
    last_id::I
end

mutable struct TournamentTree{I<:Unsigned,T<:Real}
    nodes::Vector{TTreeNode{I,T}}
    n_bins::I
end
getNode(ttree::TournamentTree, node_id::UInt32) = ttree.nodes[node_id]
getNodes(ttree::TournamentTree) = ttree.nodes
setNode!(ttree::TournamentTree, node::TTreeNode, node_id::UInt32) = ttree.nodes[node_id] = node


function fillNode!(ttree::TournamentTree{I,T}, node_id::UInt32, val::T, bin_id::I, top_id::I, bin_len::I) where {I<:Unsigned, T<:Real}
    setNode!(ttree, 
                TTreeNode(val, bin_id, top_id, bin_len),
                node_id
    )
end

#Grow tree to accomadate N bins
function growTTree!(ttree::TournamentTree{I,T}, N::I) where {I<:Unsigned, T<:Real}
    ttree.nodes = Vector{TTreeNode{I, T}}(undef, N + N - 1)
    ttree.n_bins = N
end

#Find the smallest power of 2 greater than or equal
#to the query
function getNearestPowerOf2(n::UInt32)
    n -= one(UInt32)
    n |= n >> 1
    n |= n >> 2
    n |= n >> 4
    n |= n >> 8
    n |= n >> 16
    n += one(UInt32)
    return n
end


function buildTTree!(
    ttree::TournamentTree{I, T}, #Tournament Tree
    sub_bin_ranges::Vector{UnitRange{I}}, #Ranges of `values` that are each sorted in ascending order
    n_sub_bins::UInt32, #Number of sub bin ranges to consider
    values::Vector{T} #Values 
    ) where {I<:Unsigned,T<:Real}

    #Number of leaves needs to be the next highest power of 2. 
    N = getNearestPowerOf2(n_sub_bins)
    if N+N-one(UInt32) > length(getNodes(ttree))
        growTTree!(ttree, N)
    end
    #Fill leaves (first-layer nodes) 
    leaf_idx = one(UInt32)
    for sub_bin_range in sub_bin_ranges
        top_id = first(sub_bin_range)
        last_id = last(sub_bin_range)
        fillNode!(ttree, 
                    leaf_idx, #node_id
                    values[top_id], #val
                    leaf_idx, #bin_id
                    top_id,
                    last_id
                    )
        leaf_idx += one(UInt32)
    end
    for leaf_idx in range(n_sub_bins+one(UInt32), N) #Fill placeholder leaves (if last_sub_bin_idx is not a power of 2)
        fillNode!(ttree, 
                leaf_idx,
                typemax(T),
                leaf_idx, #leaf_id
                one(I),
                one(I)
        )
    end
    #Fill remaining nodes 
    lower_node_id = 1
    upper_node_id = N + 1
    n = N >> 1
    while n > 1#node_id <= (N - 1) #While there are nodes left to fill
        start = upper_node_id
        n = n >> 1
        while upper_node_id <= start + n + 1 #Fill current layer of nodes 

            node_a, node_b = ttree.nodes[lower_node_id], ttree.nodes[lower_node_id+1]

            if getVal(node_a) <= getVal(node_b)
                ttree.nodes[upper_node_id] = node_a
            else
                ttree.nodes[upper_node_id] = node_b
            end
            lower_node_id += 2
            upper_node_id += 1
        end
    end

end

function removeSmallestElement!(
    ttree::TournamentTree{I, T},
    values_in::Vector{T},
    values_out::Vector{T},
    out_idx::Int64
) where {I<:Unsigned,T<:Real}
    #Number of bins in the merge 
    n = ttree.n_bins
    #Get node containing minimum value 
    leading_node = getNode(ttree, n + n - one(UInt32))
    #Write minimum value to output array and increase index 
    values_out[out_idx] = getVal(leading_node)
    out_idx += 1
    #Repair tree 
    top_id,last_id,bin_id = getTopID(leading_node),getLastID(leading_node),getBinID(leading_node)
    if top_id === last_id #No more elements left in the bin
        setNode!(ttree, 
                TTreeNode(
                typemax(T), #No more elements left, so make sure this bin always loses 
                bin_id,
                top_id,
                last_id),
                bin_id)
    else
        top_id += one(I)
        setNode!(ttree, 
                TTreeNode(
                values_in[top_id],
                bin_id,
                top_id,
                last_id),
                bin_id)
    end
    #If the bin_id is even, subtract one
    lower_node_id = bin_id - (bin_id%I(2) === zero(I))
    N = ttree.n_bins
    n = (lower_node_id >> 1)
    while N > 1
        node_a, node_b = getNode(ttree, lower_node_id), getNode(ttree, lower_node_id + one(I))
        lower_node_id += N - n
        if getVal(node_a) <= getVal(node_b)
            setNode!(ttree, node_a,  lower_node_id)
        else
            setNode!(ttree, node_b,  lower_node_id)
        end
        lower_node_id = lower_node_id - (lower_node_id%I(2) === zero(I))
        N = N >> 1
        n = n >> 1
    end
end
using PProf, Profile
Profile.clear()
MS_TABLE = Arrow.Table(MS_TABLE_PATH)
@profile PSMS = vcat(quantitationSearch(MS_TABLE, 
                prosit_lib["precursors"],
                prosit_lib["f_det"],
                RT_INDICES[file_id_to_parsed_name[ms_file_idx]],
                UInt32(ms_file_idx), 
                frag_err_dist_dict[ms_file_idx],
                irt_errs[ms_file_idx],
                params_,  
                ionMatches,
                ionMisses,
                IDtoCOL,
                ionTemplates,
                iso_splines,
                complex_scored_PSMs,
                complex_unscored_PSMs,
                complex_spectral_scores,
                precursor_weights,
                )...);
                pprof(;webport=58600)