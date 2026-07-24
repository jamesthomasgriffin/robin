# Raster of Bezier Intersection Neighbourhoods (ROBIN)

An algorithm for rendering text or other vector graphics, inspired by and directly comparable to [SLUG](https://github.com/EricLengyel/Slug).  The vector data is held in two objects on the GPU: 
1) the raster where each pixel contains a partial winding number (8 bits), the number of Bezier curves intersecting that pixel (8 bits), and the index of the first Bezier curve (16 bits), along with
2) the buffer of floats containing the Bezier curves indexed by the raster.
  
## This implementation
This repository contains a [LÖVR](https://github.com/bjornbytes/lovr) project.  The code is split between glsl for rendering and Lua for the creation of the ROBIN raster and curve data.  At this stage the code is not pretty, but hopefully the text rendering is.  Suggestions for improvements are welcome.
To run the demo just [download LÖVR](https://lovr.org/downloads), extract it, then drag the folder containing this project onto the LÖVR executable.
Optionally download some fonts from e.g. [Google Fonts](https://fonts.google.com/) and copy them into the fonts folder, use number keys to switch between them.

## Notes on the algorithm
ROBIN is nearly equivalent to SLUG if the raster is a `1xn` line.  The input is a sequence of quadratic Bezier curves, these curves are binned into a raster, each texel references the curves which pass through it and contains a partial calculation of the winding number for the curves which do *not* pass through it.  This means that only those curves in the neighbourhood of a point need to be intersected when computing the winding number.

Although I don't make any strong claims of speed I found this method to be about `1.5x` to `2x` as fast as SLUG which bins its curves into bands, this is for simple fonts with double digit numbers of curves.  The main advantage of ROBIN is that it scales with the number of curves in a texel neighbourhood as opposed to the number of curves that intersect a line passing through the whole glyph.  As such ROBIN sees no slow down for intricate fonts at the expense of a larger raster.  Because ROBIN is inherently more efficient than SLUG this also means that the implementation requires fewer optimisations meaning that it is actually simpler.

The memory use is harder to compare as it depends on the parameters chosen.  However even though a whole 2D raster is used, this offers the benefit that for most texels the curves are a contiguous subset of the full set of curves, meaning that most texels can reference a single unique copy of the data.  A larger raster leads to *less* floating point curve memory use!  It is certainly feasible to have the maximum of 65,536 symbols of a typical font file held in a single 2048 or 4096 square raster with a buffer of floats of a similar size for the curve data.  Though you may prefer to load the symbols in as they are needed.

