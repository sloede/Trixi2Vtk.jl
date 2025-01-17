# Create and return VTK grids that are ready to be filled with data (vtu version)
function build_vtk_grids(::Val{:vtu}, coordinates, levels, center_level_0, length_level_0,
                         n_visnodes, verbose, output_directory, is_datafile, filename)
  # Extract number of spatial dimensions
  ndims_ = size(coordinates, 1)

  # Calculate VTK points and cells
  verbose && println("| Preparing VTK cells...")
  if is_datafile
    @timeit "prepare VTK cells (node data)" begin
      vtk_points, vtk_cells = calc_vtk_points_cells(Val(ndims_), coordinates, levels,
                                                    center_level_0, length_level_0, n_visnodes)
    end
  end

  # Prepare VTK points and cells for celldata file
  @timeit "prepare VTK cells (cell data)" begin
    vtk_celldata_points, vtk_celldata_cells = calc_vtk_points_cells(Val(ndims_), coordinates,
                                                                    levels, center_level_0,
                                                                    length_level_0, 1)
  end

  # Determine output file names
  base, _ = splitext(splitdir(filename)[2])
  vtk_filename = joinpath(output_directory, base)
  vtk_celldata_filename = vtk_filename * "_celldata"

  # Open VTK files
  verbose && println("| Building VTK grid...")
  if is_datafile
    @timeit "build VTK grid (node data)" vtk_nodedata = vtk_grid(vtk_filename, vtk_points,
                                                                 vtk_cells)
  else
    vtk_nodedata = nothing
  end
  @timeit "build VTK grid (cell data)" vtk_celldata = vtk_grid(vtk_celldata_filename,
                                                                vtk_celldata_points,
                                                                vtk_celldata_cells)

  return vtk_nodedata, vtk_celldata
end


# Create and return VTK grids that are ready to be filled with data (vti version)
function build_vtk_grids(::Val{:vti}, coordinates, levels, center_level_0, length_level_0,
                         n_visnodes, verbose, output_directory, is_datafile, filename)
    # Extract number of spatial dimensions
    ndims_ = size(coordinates, 1)

    # Prepare VTK points and cells for celldata file
    @timeit "prepare VTK cells" vtk_celldata_points, vtk_celldata_cells = calc_vtk_points_cells(
        Val(ndims_), coordinates, levels, center_level_0, length_level_0, 1)

    # Determine output file names
    base, _ = splitext(splitdir(filename)[2])
    vtk_filename = joinpath(output_directory, base)
    vtk_celldata_filename = vtk_filename * "_celldata"

    # Open VTK files
    verbose && println("| Building VTK grid...")
    if is_datafile
      # Determine level-wise resolution
      max_level = maximum(levels)
      resolution = n_visnodes * 2^max_level

      Nx = Ny = resolution + 1
      dx = dy = length_level_0/resolution
      origin = center_level_0 .- 1/2 * length_level_0
      spacing = [dx, dy]
      @timeit "build VTK grid (node data)" vtk_nodedata = vtk_grid(vtk_filename, Nx, Ny,
                                                          origin=origin,
                                                          spacing=spacing)
    else
      vtk_nodedata = nothing
    end
    @timeit "build VTK grid (cell data)" vtk_celldata = vtk_grid(vtk_celldata_filename,
                                                        vtk_celldata_points,
                                                        vtk_celldata_cells)

  return vtk_nodedata, vtk_celldata
end


# Determine and return filenames for PVD fiels
function pvd_filenames(filenames, pvd, output_directory)
  # Determine pvd filename
  if !isnothing(pvd)
    # Use filename if given on command line
    filename = pvd

    # Strip of directory/extension
    filename, _ = splitext(splitdir(filename)[2])
  else
    filename = get_pvd_filename(filenames)

    # If filename is empty, it means we were not able to determine an
    # appropriate file thus the user has to supply one
    if filename == ""
      error("could not auto-detect PVD filename (input file names have no common prefix): " *
            "please provide a PVD filename name with the keyword argument `pvd=...`")
    end
  end

  # Get full filenames
  pvd_filename = joinpath(output_directory, filename)
  pvd_celldata_filename = pvd_filename * "_celldata"

  return pvd_filename, pvd_celldata_filename
end


# Determine filename for PVD file based on common name
function get_pvd_filename(filenames::AbstractArray)
  filenames = getindex.(splitdir.(filenames), 2)
  bases = getindex.(splitext.(filenames), 1)
  pvd_filename = longest_common_prefix(bases)
  return pvd_filename
end


# Determine longest common prefix
function longest_common_prefix(strings::AbstractArray)
  # Return early if array is empty
  if isempty(strings)
    return ""
  end

  # Count length of common prefix, by ensuring that all strings are long enough
  # and then comparing the next character
  len = 0
  while all(length.(strings) .> len) && all(getindex.(strings, len+1) .== strings[1][len+1])
    len +=1
  end

  return strings[1][1:len]
end


# Convert coordinates and level information to a list of points and VTK cells (2D version)
function calc_vtk_points_cells(::Val{2}, coordinates::AbstractMatrix{Float64},
                               levels::AbstractVector{Int},
                               center_level_0::AbstractVector{Float64},
                               length_level_0::Float64,
                               n_visnodes::Int=1)
  ndim = 2
  # Create point locator
  pl = PointLocator{2}(center_level_0, length_level_0, 1e-12)

  # Create arrays for points and cells
  n_elements = length(levels)
  points = Vector{SVector{2, Float64}}()
  vtk_cells = Vector{MeshCell}(undef, n_elements * n_visnodes^ndim)
  point_ids = Vector{Int}(undef, 2^ndim)

  # Reshape cell array for easy-peasy access
  reshaped = reshape(vtk_cells, n_visnodes, n_visnodes, n_elements)

  # Create VTK cell for each Trixi element
  for element_id in 1:n_elements
    # Extract cell values
    cell_x = coordinates[1, element_id]
    cell_y = coordinates[2, element_id]
    cell_dx = length_level_0 / 2^levels[element_id]

    # Adapt to visualization nodes for easy-to-understand loops
    dx = cell_dx / n_visnodes
    x_lowerleft = cell_x - cell_dx/2 - dx/2
    y_lowerleft = cell_y - cell_dx/2 - dx/2

    # Create cell for each visualization node
    for j = 1:n_visnodes
      for i = 1:n_visnodes
        # Determine x and y
        x = x_lowerleft + i * dx
        y = y_lowerleft + j * dx

        # Get point id for each vertex
        point_ids[1] = insert!(pl, points, (x - dx/2, y - dx/2))
        point_ids[2] = insert!(pl, points, (x + dx/2, y - dx/2))
        point_ids[3] = insert!(pl, points, (x - dx/2, y + dx/2))
        point_ids[4] = insert!(pl, points, (x + dx/2, y + dx/2))

        # Add cell
        reshaped[i, j, element_id] = MeshCell(VTKCellTypes.VTK_PIXEL, copy(point_ids))
      end
    end
  end

  # Convert array-of-points to two-dimensional array
  vtk_points = Matrix{Float64}(undef, ndim, length(points))
  for point_id in 1:length(points)
    vtk_points[1, point_id] = points[point_id][1]
    vtk_points[2, point_id] = points[point_id][2]
  end

  return vtk_points, vtk_cells
end


# Convert coordinates and level information to a list of points and VTK cells (3D version)
function calc_vtk_points_cells(::Val{3}, coordinates::AbstractMatrix{Float64},
                               levels::AbstractVector{Int},
                               center_level_0::AbstractVector{Float64},
                               length_level_0::Float64,
                               n_visnodes::Int=1)
  ndim = 3
  # Create point locator
  pl = PointLocator{3}(center_level_0, length_level_0, 1e-12)

  # Create arrays for points and cells
  n_elements = length(levels)
  points = Vector{SVector{3, Float64}}()
  vtk_cells = Vector{MeshCell}(undef, n_elements * n_visnodes^ndim)
  point_ids = Vector{Int}(undef, 2^ndim)

  # Reshape cell array for easy-peasy access
  reshaped = reshape(vtk_cells, n_visnodes, n_visnodes, n_visnodes, n_elements)

  # Create VTK cell for each Trixi element
  for element_id in 1:n_elements
    # Extract cell values
    cell_x = coordinates[1, element_id]
    cell_y = coordinates[2, element_id]
    cell_z = coordinates[3, element_id]
    cell_dx = length_level_0 / 2^levels[element_id]

    # Adapt to visualization nodes for easy-to-understand loops
    dx = cell_dx / n_visnodes
    x_lowerleft = cell_x - cell_dx/2 - dx/2
    y_lowerleft = cell_y - cell_dx/2 - dx/2
    z_lowerleft = cell_z - cell_dx/2 - dx/2

    # Create cell for each visualization node
    for k = 1:n_visnodes, j = 1:n_visnodes, i = 1:n_visnodes
      # Determine x and y
      x = x_lowerleft + i * dx
      y = y_lowerleft + j * dx
      z = z_lowerleft + k * dx

      # Get point id for each vertex
      point_ids[1] = insert!(pl, points, (x - dx/2, y - dx/2, z - dx/2))
      point_ids[2] = insert!(pl, points, (x + dx/2, y - dx/2, z - dx/2))
      point_ids[3] = insert!(pl, points, (x - dx/2, y + dx/2, z - dx/2))
      point_ids[4] = insert!(pl, points, (x + dx/2, y + dx/2, z - dx/2))
      point_ids[5] = insert!(pl, points, (x - dx/2, y - dx/2, z + dx/2))
      point_ids[6] = insert!(pl, points, (x + dx/2, y - dx/2, z + dx/2))
      point_ids[7] = insert!(pl, points, (x - dx/2, y + dx/2, z + dx/2))
      point_ids[8] = insert!(pl, points, (x + dx/2, y + dx/2, z + dx/2))

      # Add cell
      reshaped[i, j, k, element_id] = MeshCell(VTKCellTypes.VTK_VOXEL, copy(point_ids))
    end
  end

  # Convert array-of-points to two-dimensional array
  vtk_points = Matrix{Float64}(undef, ndim, length(points))
  for point_id in 1:length(points)
    vtk_points[1, point_id] = points[point_id][1]
    vtk_points[2, point_id] = points[point_id][2]
    vtk_points[3, point_id] = points[point_id][3]
  end

  return vtk_points, vtk_cells
end

