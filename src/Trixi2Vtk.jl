module Trixi2Vtk

# Include other packages
using Glob: glob
using HDF5: h5open, attributes, haskey
using ProgressMeter: @showprogress, Progress, next!
using StaticArrays: SVector
using TimerOutputs
using Trixi: Trixi, transfinite_mapping
using WriteVTK: vtk_grid, MeshCell, VTKCellTypes, vtk_save, paraview_collection, VTKPointData

# Include all top-level submodule files
include("interpolation.jl")
include("interpolate.jl")
include("io.jl")
include("pointlocators.jl")
include("vtktools.jl")

# Include top-level conversion method
include("convert.jl")


# export types/functions that define the public API of Trixi2Vtk
export trixi2vtk


end # module Trixi2Vtk
