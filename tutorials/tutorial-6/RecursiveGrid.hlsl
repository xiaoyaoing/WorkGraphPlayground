// This file is part of the AMD & HSC Work Graph Playground.
//
// Copyright (C) 2024 Advanced Micro Devices, Inc. and Coburg University of Applied Sciences and Arts.
// All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files(the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and /or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions :
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#include "Common.h"

// Mandelbrot.h contains functionality for computing and drawing the Mandelbrot fractal
#include "Mandelbrot.h"

// When you have reached this tutorial, you have learned all the Work Graphs
// concepts that we consider important for beginners! The point of this last
// tutorial is to give you a tougher Work Graph problem to think about, possibly
// even to take home.

// The provided code renders a small zoom animation into the Mandelbrot set.
// In the implementation provided, each pixel's "dwell", thus the number of 
// iterations, is computed individually. With Work Graphs, we can optimize 
// this using Mariani's algorithm:
// All "structures" in the Mandelbrot set are known to be connected. Therefore,
// regions that have the same dwell around their boundary are guaranteed to have
// the same dwell for all the pixels inside. With Work Graphs, we can subdivide
// the screen into a coarse grid. Next, each grid cell's boundary is evaluated.
// If not all pixels of the boundary are the same dwell, the cell is subdivided
// and the grid recurses. If all dwell values are equal, the cell is filled with
// the specific color. Your task: implement this algorithm in work graphs!

// Note that the solution provided is far from optimal and intentionally kept
// simple, feel free to share your own faster solution!

struct NaiveMandelbrotRecord {
    uint2 dispatchGrid : SV_DispatchGrid;
};

[Shader("node")]
[NodeIsProgramEntry]
[NodeLaunch("thread")]
[NodeId("Entry")]
void EntryNode(
    [MaxRecords(1)]
    [NodeId("NaiveMandelbrot")]
    NodeOutput<NaiveMandelbrotRecord> mandelbrotOutput
)
{
    ThreadNodeOutputRecords<NaiveMandelbrotRecord> outputRecord =
        mandelbrotOutput.GetThreadNodeOutputRecords(1);

    outputRecord.Get().dispatchGrid = (RenderSize + 7) / 8;

    outputRecord.OutputComplete();
}

[Shader("node")]
[NodeLaunch("broadcasting")]
[NodeMaxDispatchGrid(1024, 1024, 1)]
[NumThreads(8, 8, 1)]
[NodeId("NaiveMandelbrot")]
void NaiveMandelbrotNode(
    uint2 dtid : SV_DispatchThreadID,
    DispatchNodeInputRecord<NaiveMandelbrotRecord> inputRecord
)
{
    if (all(dtid < RenderSize)) {
        const int dwell = GetPixelDwell(dtid);

        RenderTarget[dtid] = float4(DwellToColor(dwell), 1);
    }
}
