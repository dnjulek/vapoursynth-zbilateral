# vapoursynth-zbilateral
[![Linux](https://github.com/dnjulek/vapoursynth-zbilateral/actions/workflows/linux-build.yml/badge.svg)](https://github.com/dnjulek/vapoursynth-zbilateral/actions/workflows/linux-build.yml)
[![Windows](https://github.com/dnjulek/vapoursynth-zbilateral/actions/workflows/windows-build.yml/badge.svg)](https://github.com/dnjulek/vapoursynth-zbilateral/actions/workflows/windows-build.yml)

A faster version of [VapourSynth-Bilateral](https://github.com/HomeOfVapourSynthEvolution/VapourSynth-Bilateral) written in zig.\
Currently only ``algorithm=2`` is working (and I believe no one uses 1, since it's dead slow).

## Usage
```python
zbilateral.Bilateral(vnode clip[, vnode ref, float[] sigmaS=3.0, float[] sigmaR=0.02, int[] planes=[], int[] algorithm=0, int[] PBFICnum=[]])
```
### Parameters:

- clip:\
    A clip to process.
- ref:\
    Reference clip to calculate range weight.\
    Specify it if you want to perform joint/cross Bilateral filter.
- sigmaS: (Default: 3.0)\
    sigma of Gaussian function to calculate spatial weight.\
    The scale of this parameter is equivalent to pixel distance.\
    Larger sigmaS results in larger filtering radius as well as stronger smoothing.\
    Use an array to assign sigmaS for each plane. If sigmaS for the second plane is not specified, it will be set according to the sigmaS of first plane and sub-sampling.

- sigmaR: (Default: 0.02)\
    sigma of Gaussian function to calculate range weight.\
    The scale of this parameter is the same as pixel value ranging in [0,1].\
    Smaller sigmaR preserves edges better, may also leads to weaker smoothing.\
    Use an array to specify sigmaR for each plane, otherwise the same sigmaR is used for all the planes.

- planes:\
    An array to specify which planes to process.\
    By default, chroma planes are not processed.

- algorithm: (Default: 0)\
    0 = Automatically determine the algorithm according to sigmaS, sigmaR and PBFICnum.\
    1 = O(1) Bilateral filter uses quantized PBFICs. (IMO it should be O(PBFICnum))\
    2 = Bilateral filter with truncated spatial window and sub-sampling. O(sigmaS^2)

- PBFICnum:\
    Number of PBFICs used in algorithm=1.\
    Default: 4 when sigmaR>=0.08. It will increase as sigmaR decreases, up to 32. For chroma plane default value will be odd to better preserve neutral value of chromiance.\
    Available range is [2,256].\
    Use an array to specify PBFICnum for each plane.
## Building
Zig ver >= 0.12.0-dev.15

``zig build -Doptimize=ReleaseFast``

If you don't have vapoursynth installed you must provide the include path with ``-Dvsinclude=...``.

## TODO
1. algorithm=1.