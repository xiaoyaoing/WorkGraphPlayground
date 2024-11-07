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

// This tutorial teaches about input scratch storage and synchronization with
// Read/Write records. An input record to a broadcasting node can be defined as
// read/write. This enables the nodes to use it as scratch memory. Furthermore,
// RW records have a function FinishedCrossGroupSharing() which returns true for
// the last launched group. This allows us to launch a grid of groups, wait for
// all of them to finish, and then perform some extra work on the last group to
// finish.

// Your goal is to draw the axis-aligned bounding box of the sketch animation by
// input sharing.

// [Task 3 Solution]:
struct [NodeTrackRWInputSharing] ComputeBoundingBoxRecord {
    int2 aabbmin;
    int2 aabbmax;
};

[Shader("node")]
[NodeIsProgramEntry]
[NodeLaunch("thread")]
[NodeId("Entry")]
void EntryNode(
    [MaxRecords(1)]
    [NodeId("ComputeBoundingBox")]
    NodeOutput<ComputeBoundingBoxRecord> output
)
{
    GroupNodeOutputRecords<ComputeBoundingBoxRecord> outputRecord =
        output.GetGroupNodeOutputRecords(1);

    // Initialize min and max values.
    outputRecord.Get().aabbmin = RenderSize;
    outputRecord.Get().aabbmax = int2(0, 0);

    outputRecord.OutputComplete();
}

static const int numPoints = 1024;
static const int groupSize = 32;
static const int numGroups = (numPoints + groupSize - 1) / groupSize;

[Shader("node")]
[NodeLaunch("broadcasting")]
[NodeDispatchGrid(numGroups, 1, 1)]
[NodeId("ComputeBoundingBox")]
[NumThreads(groupSize, 1, 1)]
void ComputeBoundingBoxNode(
    uint gtid : SV_GroupThreadID,
    uint dtid : SV_DispatchThreadID,

    // [Task 1 Solution]: We need the globallycoherent attribute so that the
    //     data-reads and data-writes bypass the caches.
    globallycoherent RWDispatchNodeInputRecord<ComputeBoundingBoxRecord> inputRecord
)
{
    // Timestamp offset of the current circle
    const float t      = float(dtid) / numPoints;
    const int2  pixel  = RenderSize * .5 + 0.9 * RenderSize * float2(
        random::PerlinNoise2D(float2('x', 2 * Time + t * 2)),
        random::PerlinNoise2D(float2('y', 2 * Time + t * 2)));
    // Radius of the circle to draw. This will also be important for the bounding box computation.
    // The radius will slowly get smaller over time.
    const float radius = pow(t, 2) * 15;
    // Draw a circle around the sampled pixel. The color slowly fades out over time.
    FillCircle(pixel, radius, lerp(float3(1, 1, 1), float3(0, 0, 1), pow(t, 2)));

    // [Task 2 Solution]: We use atomic min/max operation on the "aabbmin" and
    //     "aabbmax" members of the input record. We padded the pixel position
    //     with the radius of the current circle, and as this computation is
    //     done with floating-point numbers, we round towards the outside of the
    //     bounding box (i.e., floor for minimum and ceil for maximum).
    InterlockedMin(inputRecord.Get().aabbmin.x, floor(pixel.x - radius));
    InterlockedMin(inputRecord.Get().aabbmin.y, floor(pixel.y - radius));
    InterlockedMax(inputRecord.Get().aabbmax.x, ceil(pixel.x + radius));
    InterlockedMax(inputRecord.Get().aabbmax.y, ceil(pixel.y + radius));

    // Ensure all groups and threads have finished writing. 
    // Required, because atomic ops do not act as barriers and return immediatley after calling.
    Barrier(NODE_INPUT_MEMORY, DEVICE_SCOPE | GROUP_SYNC);

    // [Task 3 Solution]: "FinishedCrossGroupSharing" only returns true for the
    //     last thread group that calls this function. Thus, once
    //     "FinishedCrossGroupSharing" returns true, we know that all other
    //     thread groups have finished and thus "inputRecord.Get().aabbmin" and
    //     "inputRecord.Get().aabbmax" now contain the computed bounding box.
    
    if(!inputRecord.FinishedCrossGroupSharing()) return;
    
    // Only one, i.e., the last, thread group arrives here. 
    // Thus, only the last thread group gets to draw the bounding box.
    // Draw the bounding box with the first thread in the thread group.
    if(gtid == 0) {
        DrawRect(inputRecord.Get().aabbmin, inputRecord.Get().aabbmax, 1);
    }
}
