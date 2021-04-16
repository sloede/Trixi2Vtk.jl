
# Interpolate data from input format to desired output format (vtu version)
function interpolate_data(::Val{:vtu}, input_data, coordinates, levels,
                          center_level_0, length_level_0, n_visnodes, verbose)
  return raw2visnodes(input_data, n_visnodes)
end


# Interpolate data from input format to desired output format (vti version)
function interpolate_data(::Val{:vti}, input_data, coordinates, levels,
                          center_level_0, length_level_0, n_visnodes, verbose)
  # Normalize element coordinates: move center to (0, 0) and domain size to [-1, 1]²
  normalized_coordinates = similar(coordinates)
  for element_id in axes(coordinates, 2)
    @views normalized_coordinates[:, element_id] .= (
        (coordinates[:, element_id] .- center_level_0) ./ (length_level_0 / 2 ))
  end

  # Determine level-wise resolution
  max_level = maximum(levels)
  resolution = n_visnodes * 2^max_level

  # nvisnodes_per_level is an array (accessed by "level + 1" to accommodate
  # level-0-cell) that contains the number of visualization nodes for any
  # refinement level to visualize on an equidistant grid
  nvisnodes_per_level = [2^(max_level - level)*n_visnodes for level in 0:max_level]

  # Interpolate unstructured DG data to structured data
  structured_data = unstructured2structured(input_data, normalized_coordinates, levels,
                                            resolution, nvisnodes_per_level)

  return structured_data
end


# Interpolate unstructured DG data to structured data (cell-centered)
function unstructured2structured(unstructured_data::AbstractArray{Float64},
                                 normalized_coordinates::AbstractArray{Float64},
                                 levels::AbstractArray{Int}, resolution::Int,
                                 nvisnodes_per_level::AbstractArray{Int})
  # Extract number of spatial dimensions
  ndims_ = size(normalized_coordinates, 1)

  # Extract data shape information
  n_nodes_in, _, n_elements, n_variables = size(unstructured_data)

  # Get node coordinates for DG locations on reference element
  nodes_in, _ = gauss_lobatto_nodes_weights(n_nodes_in)

  # Calculate interpolation vandermonde matrices for each level
  max_level = length(nvisnodes_per_level) - 1
  vandermonde_per_level = []
  for l in 0:max_level
    n_nodes_out = nvisnodes_per_level[l + 1]
    dx = 2 / n_nodes_out
    nodes_out = collect(range(-1 + dx/2, 1 - dx/2, length=n_nodes_out))
    push!(vandermonde_per_level, polynomial_interpolation_matrix(nodes_in, nodes_out))
  end

  # For each element, calculate index position at which to insert data in global data structure
  lower_left_index = element2index(normalized_coordinates, levels, resolution, nvisnodes_per_level)

  # Create output data structure
  structured = Array{Float64}(undef, resolution, resolution, n_variables)

  # For each variable, interpolate element data and store to global data structure
  for v in 1:n_variables
    # Reshape data array for use in interpolate_nodes function
    reshaped_data = reshape(unstructured_data[:, :, :, v], 1, n_nodes_in, n_nodes_in, n_elements)

    for element_id in 1:n_elements
      # Extract level for convenience
      level = levels[element_id]

      # Determine target indices
      n_nodes_out = nvisnodes_per_level[level + 1]
      first = lower_left_index[:, element_id]
      last = first .+ (n_nodes_out - 1)

      # Interpolate data
      vandermonde = vandermonde_per_level[level + 1]
      structured[first[1]:last[1], first[2]:last[2], v] .= (
          reshape(interpolate_nodes(reshaped_data[:, :, :, element_id], vandermonde, 1),
                  n_nodes_out, n_nodes_out))
    end
  end

  # Return as one 1D array for each variable
  return reshape(structured, resolution^ndims_, n_variables)
end


# For a given normalized element coordinate, return the index of its lower left
# contribution to the global data structure
function element2index(normalized_coordinates::AbstractArray{Float64}, levels::AbstractArray{Int},
                       resolution::Int, nvisnodes_per_level::AbstractArray{Int})
  # Extract number of spatial dimensions
  ndims_ = size(normalized_coordinates, 1)

  n_elements = length(levels)

  # First, determine lower left coordinate for all cells
  dx = 2 / resolution
  lower_left_coordinate = Array{Float64}(undef, ndims_, n_elements)
  for element_id in 1:n_elements
    nvisnodes = nvisnodes_per_level[levels[element_id] + 1]
    lower_left_coordinate[1, element_id] = (
        normalized_coordinates[1, element_id] - (nvisnodes - 1)/2 * dx)
    lower_left_coordinate[2, element_id] = (
        normalized_coordinates[2, element_id] - (nvisnodes - 1)/2 * dx)
  end

  # Then, convert coordinate to global index
  indices = coordinate2index(lower_left_coordinate, resolution)

  return indices
end


# Find 2D array index for a 2-tuple of normalized, cell-centered coordinates (i.e., in [-1,1])
function coordinate2index(coordinate, resolution::Integer)
  # Calculate 1D normalized coordinates
  dx = 2/resolution
  mesh_coordinates = collect(range(-1 + dx/2, 1 - dx/2, length=resolution))

  # Find index
  id_x = searchsortedfirst.(Ref(mesh_coordinates), coordinate[1, :], lt=(x,y)->x .< y .- dx/2)
  id_y = searchsortedfirst.(Ref(mesh_coordinates), coordinate[2, :], lt=(x,y)->x .< y .- dx/2)
  return transpose(hcat(id_x, id_y))
end


# Interpolate to visualization nodes
function raw2visnodes(data_gl::AbstractArray{Float64}, n_visnodes::Int)
  # Extract number of spatial dimensions
  ndims_ = ndims(data_gl) - 2

  # Extract data shape information
  n_nodes_in = size(data_gl, 1)
  n_elements = size(data_gl, ndims_ + 1)
  n_variables = size(data_gl, ndims_ + 2)

  # Get node coordinates for DG locations on reference element
  nodes_in, _ = gauss_lobatto_nodes_weights(n_nodes_in)

  # Calculate Vandermonde matrix
  dx = 2 / n_visnodes
  nodes_out = collect(range(-1 + dx/2, 1 - dx/2, length=n_visnodes))
  vandermonde = polynomial_interpolation_matrix(nodes_in, nodes_out)

  if ndims_ == 2
    # Create output data structure
    data_vis = Array{Float64}(undef, n_visnodes, n_visnodes, n_elements, n_variables)

    # For each variable, interpolate element data and store to global data structure
    for v in 1:n_variables
      # Reshape data array for use in interpolate_nodes function
      @views reshaped_data = reshape(data_gl[:, :, :, v], 1, n_nodes_in, n_nodes_in, n_elements)

      # Interpolate data to visualization nodes
      for element_id in 1:n_elements
        @views data_vis[:, :, element_id, v] .= reshape(
            interpolate_nodes(reshaped_data[:, :, :, element_id], vandermonde, 1),
            n_visnodes, n_visnodes)
      end
    end
  elseif ndims_ == 3
    # Create output data structure
    data_vis = Array{Float64}(undef, n_visnodes, n_visnodes, n_visnodes, n_elements, n_variables)

    # For each variable, interpolate element data and store to global data structure
    for v in 1:n_variables
      # Reshape data array for use in interpolate_nodes function
      @views reshaped_data = reshape(data_gl[:, :, :, :, v],
                                     1, n_nodes_in, n_nodes_in, n_nodes_in, n_elements)

      # Interpolate data to visualization nodes
      for element_id in 1:n_elements
        @views data_vis[:, :, :, element_id, v] .= reshape(
            interpolate_nodes(reshaped_data[:, :, :, :, element_id], vandermonde, 1),
            n_visnodes, n_visnodes, n_visnodes)
      end
    end
  else
    error("Unsupported number of spatial dimensions: ", ndims_)
  end

  # Return as one 1D array for each variable
  return reshape(data_vis, n_visnodes^ndims_ * n_elements, n_variables)
end


# Interpolate data from input format to desired output format (vtu version)
function interpolate_data(::Val{:vts}, input_data, mesh, n_nodes, n_visnodes, verbose)
  # Calculate sizes and index mappings
  linear_indices = LinearIndices(size(mesh))
  Nx = size(mesh, 1)
  Ny = size(mesh, 2)
  nvisnodes = n_nodes - 1
  Ni = Nx * nvisnodes
  Nj = Ny * nvisnodes
  n_variables = last(size(input_data))
  basis = Trixi.LobattoLegendreBasis(n_nodes - 1)

  # Create output array
  interpolated = Array{Float64}(undef, Ni + 1, Nj + 1, n_variables)

  # OBS! The following algorithm is not symmetric: For all nodes on the element surfaces, the value
  # from the element with the higher (i,j) index is used, i.e., some of the solution is lost

  for v in 1:n_variables
    # Compute vertex coordinates for all visualization nodes except the last layer of nodex in +x/+y
    linear_indices = LinearIndices(size(mesh))
    for cell_y in axes(mesh, 2), cell_x in axes(mesh, 1)
      for j in Trixi.eachnode(basis), i in Trixi.eachnode(basis)
        index_x = (cell_x - 1) * (n_nodes - 1) + i
        index_y = (cell_y - 1) * (n_nodes - 1) + j
        interpolated[index_x, index_y, v] = input_data[i, j, linear_indices[cell_x, cell_y], v]
      end
    end

    # Compute vertex locations in +x direction
    for cell_y in axes(mesh, 2), cell_x in Nx
      for j in Trixi.eachnode(basis)
        index_y = (cell_y - 1) * (n_nodes - 1) + j
        interpolated[end, index_y, v] = input_data[end, j, linear_indices[cell_x, cell_y], v]
      end
    end

    # Compute vertex locations in +y direction
    for cell_y in Ny, cell_x in axes(mesh, 1)
      for i in Trixi.eachnode(basis)
        index_x = (cell_x - 1) * (n_nodes - 1) + i
        interpolated[index_x, end, v] = input_data[i, end, linear_indices[cell_x, cell_y], v]
      end
    end
  end

  # Compute the value for each visualization node (= cell of structured visualization mesh) as the
  # mean of the four nodal DG values that make up its corners
  # for v in 1:n_variables
  #   for cell_y in axes(mesh, 2), cell_x in axes(mesh, 1)
  #     for j in 1:nvisnodes, i in 1:nvisnodes
  #       index_x = (cell_x - 1) * nvisnodes + i
  #       index_y = (cell_y - 1) * nvisnodes + j
  #       interpolated[index_x, index_y, v] =
  #           (input_data[i,   j,   linear_indices[cell_x, cell_y], v] + 
  #            input_data[i+1, j,   linear_indices[cell_x, cell_y], v] + 
  #            input_data[i,   j+1, linear_indices[cell_x, cell_y], v] + 
  #            input_data[i+1, j+1, linear_indices[cell_x, cell_y], v]) / 4
  #     end
  #   end
  # end

  return interpolated
end
