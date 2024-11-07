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

// Enable/disable visualization of grid cells with same dwell values.
#define VISUALIZE_GRID_CELLS 1

struct MandelbrotGridRecord {
    uint2 dispatchGrid : SV_DispatchGrid;
};

struct NaiveMandelbrotRecord {
    int2 topLeft;
    int  size;
};

struct [NodeTrackRWInputSharing] MarianiSilverRecord {
    uint dispatchSize : SV_DispatchGrid;
    int2 topLeft;
    int  size;
    // Shared min and max dwell values for grid cell.
    // If minDwell = maxDwell, then all tested pixels have the same dwell.
    // That is why we need the NodeTrackRWInputSharing above.
    int minDwell;
    int maxDwell;
};

struct MandelbrotFillRecord {
    uint2  dispatchGrid : SV_DispatchGrid;
    int2   topLeft;
    int    size;
    float3 color;
};


static const int maxResolution = 4096;
static const int tilePow = 8;
static const int tileSize = 3 * (1l << tilePow) - 2;
static const int maxTilesPerAxis = min(32, maxResolution / tileSize);

static const int minSize = 16;

[Shader("node")]
[NodeIsProgramEntry]
[NodeLaunch("thread")]
[NodeId("Entry")]
void EntryNode(
    [MaxRecords(1)]
    [NodeId("MandelbrotGrid")]
    NodeOutput<MandelbrotGridRecord> gridOutput
)
{
    ThreadNodeOutputRecords<MandelbrotGridRecord> outputRecord =
        gridOutput.GetThreadNodeOutputRecords(1);

    outputRecord.Get().dispatchGrid = DivideAndRoundUp(RenderSize, 8 * tileSize);

    outputRecord.OutputComplete();
}

[Shader("node")]
[NodeLaunch("broadcasting")]
[NodeIsProgramEntry]
[NodeMaxDispatchGrid(maxTilesPerAxis, maxTilesPerAxis, 1)]
[NodeId("MandelbrotGrid")]
[NumThreads(8, 8, 1)]
void MandelbrotGridNode(
    uint2 dtid : SV_DispatchThreadID,

    DispatchNodeInputRecord<MandelbrotGridRecord> inputRecord,

    [MaxRecords(8 * 8)]
    [NodeId("MandelbrotMarianiSilver")]
    NodeOutput<MarianiSilverRecord> mandelbrotOutput
)
{
    const int2 topLeft   = dtid * tileSize;
    const bool hasOutput = all(topLeft < RenderSize);

    ThreadNodeOutputRecords<MarianiSilverRecord> outputRecord =
        mandelbrotOutput.GetThreadNodeOutputRecords(hasOutput);

    if(hasOutput){
        outputRecord.Get().dispatchSize = DivideAndRoundUp(tileSize, 8);
        outputRecord.Get().topLeft      = topLeft;
        outputRecord.Get().size         = tileSize;
        outputRecord.Get().minDwell     = maxIteration;
        outputRecord.Get().maxDwell     = 0;
    }

    outputRecord.OutputComplete();
}

[Shader("node")]
[NodeLaunch("broadcasting")]
[NodeMaxDispatchGrid((tileSize + 7) / 8, (tileSize + 7) / 8, 1)]
[NodeId("MandelbrotFill")]
[NumThreads(8, 8, 1)]
void MandelbrotFillNode(
    uint2 dtid : SV_DispatchThreadID,

    DispatchNodeInputRecord<MandelbrotFillRecord> inputRecord)
{
    const MandelbrotFillRecord record = inputRecord.Get();

#if VISUALIZE_GRID_CELLS
    // check if dtid is within record size and not along the outer edge.
    // The outer edge is left blank to visualize grid cells.
    if (all(dtid > 0) && all(dtid < (record.size - 1))) {
#else
    // check if dtid is within record size
    if (all(dtid < record.size)) {
#endif
        const int2 pixel = record.topLeft + dtid;

        if (all(pixel >= 0) && all(pixel < RenderSize)) {
            RenderTarget[pixel] = float4(record.color, 1);
        }
    }
}

[Shader("node")]
[NodeLaunch("broadcasting")]
[NodeDispatchGrid(1, 1, 1)]
[NodeId("MandelbrotNaive")]
[NumThreads(minSize, minSize, 1)]
void MandelbrotNaiveNode(
    uint2 gtid : SV_GroupThreadID,

    DispatchNodeInputRecord<NaiveMandelbrotRecord> inputRecord
)
{
    const NaiveMandelbrotRecord record = inputRecord.Get();

    if (all(gtid < record.size)) {
        const int2 pixel = record.topLeft + gtid;

        if (all(pixel >= 0) && all(pixel < RenderSize)) {
            const int dwell = GetPixelDwell(pixel);

            RenderTarget[pixel] = float4(DwellToColor(dwell), 1);
        }
    }
}

[Shader("node")]
[NodeLaunch("broadcasting")]
[NodeMaxRecursionDepth(12)]
[NodeMaxDispatchGrid((tileSize + 7) / 8, 1, 1)]
[NodeId("MandelbrotMarianiSilver")]
[NumThreads(8, 4, 1)]
void MandelbrotMarianiSilverNode(
    uint2 gtid : SV_GroupThreadID,
    uint2 dtid : SV_DispatchThreadID,

    globallycoherent RWDispatchNodeInputRecord<MarianiSilverRecord> inputRecord,

    [MaxRecords(4)]
    [NodeId("MandelbrotMarianiSilver")]
    NodeOutput<MarianiSilverRecord> recursiveOutput,

    [MaxRecordsSharedWith(recursiveOutput)]
    [NodeId("MandelbrotNaive")]
    NodeOutput<NaiveMandelbrotRecord> naiveOutput,

    [MaxRecordsSharedWith(recursiveOutput)]
    [NodeId("MandelbrotFill")]
    NodeOutput<MandelbrotFillRecord> fillOutput
)
{
    int  size    = inputRecord.Get().size;
    int2 topLeft = inputRecord.Get().topLeft;

    // Number of pixels along one edge to check
    const int pixelsOnEdge  = size - 1;
    // Required number of matching pixels (=votes) in order to determine area as single color.
    const int requiredVotes = pixelsOnEdge * 4;

    if (dtid.x < pixelsOnEdge) {
        // Lookup for side of the tile to test
        const int4 lookup = int4(0, dtid.x, size-1, size - 1 - dtid.x);
        // Compute pixel position to test
        const int2 pixel  = topLeft + int2(lookup[(gtid.y + 1) % 4], lookup[gtid.y]);

        const int dwell = GetPixelDwell(pixel);

        // Update min/max to check if all threads have the same dwell
        InterlockedMin(inputRecord.Get().minDwell, dwell);
        InterlockedMax(inputRecord.Get().maxDwell, dwell);

        RenderTarget[pixel] = float4(DwellToColor(dwell), 1);
    }

    topLeft += int2(1, 1);
    size    -= 2;

    // Ensure all groups and threads have finished writing
    Barrier(NODE_INPUT_MEMORY, DEVICE_SCOPE | GROUP_SYNC);

    if (!inputRecord.FinishedCrossGroupSharing()) {
        return;
    }

    const bool allEqual           = inputRecord.Get().minDwell == inputRecord.Get().maxDwell;
    const bool hasFillOutput      = allEqual;
    const bool hasNaiveOutput     = !allEqual &&
                                    ((GetRemainingRecursionLevels() == 0) || (size < minSize));
    const bool hasRecursiveOutput = !allEqual && !hasNaiveOutput;

    GroupNodeOutputRecords<MandelbrotFillRecord> fillOutputRecord =
        fillOutput.GetGroupNodeOutputRecords(hasFillOutput);

    if (hasFillOutput) {
        fillOutputRecord.Get().dispatchGrid = DivideAndRoundUp(size, 8);
        fillOutputRecord.Get().topLeft      = topLeft;
        fillOutputRecord.Get().size         = size;
        fillOutputRecord.Get().color        = DwellToColor(inputRecord.Get().minDwell);
    }

    fillOutputRecord.OutputComplete();

    GroupNodeOutputRecords<NaiveMandelbrotRecord> naiveOutputRecord =
        naiveOutput.GetGroupNodeOutputRecords(hasNaiveOutput);

    if (hasNaiveOutput) {
        naiveOutputRecord.Get().topLeft = topLeft;
        naiveOutputRecord.Get().size = size;
    }

    naiveOutputRecord.OutputComplete();

    GroupNodeOutputRecords<MarianiSilverRecord> recursiveOutputRecord =
        recursiveOutput.GetGroupNodeOutputRecords(hasRecursiveOutput? 4 : 0);

    if (hasRecursiveOutput) {
        // Only first threads in x dimensions write outputs.
        if (gtid.x == 0) {
            // Coordinate in 2x2 grid of records to emit.
            // +---+---+
            // | 0 | 1 |
            // +---+---+
            // | 2 | 3 |
            // +---+---+
            const int2 coord       = int2(gtid.y % 2, gtid.y / 2);
            // Size is always multiple of 2, thus we can split the current grid cell into
            // 2x2 grid cells with equal size.
            const int  nextSize    = size / 2;
            const int2 nextTopLeft = topLeft + coord * nextSize;

            recursiveOutputRecord.Get(gtid.y).dispatchSize = DivideAndRoundUp(nextSize, 8);
            recursiveOutputRecord.Get(gtid.y).topLeft      = nextTopLeft;
            recursiveOutputRecord.Get(gtid.y).size         = nextSize;
            recursiveOutputRecord.Get(gtid.y).minDwell     = maxIteration;
            recursiveOutputRecord.Get(gtid.y).maxDwell     = 0;
        }
    }

    recursiveOutputRecord.OutputComplete();
}

