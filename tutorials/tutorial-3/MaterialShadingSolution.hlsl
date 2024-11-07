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

// Scene.h contains functionality for tracing rays into the scene and also
// contains the material shading functions.
// !! IMPORTANT: if you are using the WARP software adapter,
//    please consider increasing SHADING_RATE in Scene.h !!
#include "Scene.h"

// Record for broadcasting nodes to launch one thread per sample (samples are scaled by SHADING_RATE in Scene.h).
struct RenderSceneRecord {
    uint2 dispatchGrid : SV_DispatchGrid;
};

// In this sample solution, we use the following work graph
// to shade each pixel on screen with a different thread-launch node.
//
// +-------+         +-------------+         +------------------------+
// | Entry |-------->| RenderScene |-------->|     ShadePixel[3]      |
// +-------+         +-------------+         |========================|
//                                           | Nodes in NodeArray:    |
//                                           | [0]: ShadePixel_Sky    |
//                                           | [1]: ShadePixel_Sphere |
//                                           | [2]: ShadePixel_Plane  |
//                                           +------------------------+

// [Task 1 Solution]:
// Record to shade a single sample (pixel)
// Produced by "RenderScene", consumed by "ShadePixel" node array below.
struct PixelRecord {
    // Pixel position of sample/pixel to shade
    uint2 pixel;
    // Ray information (required for shading functions)
    Ray   ray;
    // Ray hit distance (required for shading functions)
    float hitDistance;
};

// ============== "ShadePixel" Node Array =============
// [Task 2 Solution]: The "ShadePixel" node array below provides a dedicated thread-launch node
//                    for each of the three different materials.
//                    These nodes are joined to a node array using the [NodeId("ShadePixel", (uint)RayHit::XXX)] attribute.

[Shader("node")]
// NodeId attribute has to be used when specifying node array to set the node array index (second parameter).
// The node array index has to be of type uint, but enums such as RayHit::Material can also be used, when cast to uint.
[NodeId("ShadePixel", (uint)RayHit::Sky)]
// Each sample only requires a single thread to compute the output, thus we use thread launch here.
[NodeLaunch("thread")]
void ShadePixel_Sky(ThreadNodeInputRecord<PixelRecord> input)
{
    // Read input record
    const PixelRecord record = input.Get();

    // Compute color based on material shading function
    const float4 color = ShadeSky(record.ray);

    // Write color to output pixel(s)
    WritePixel(record.pixel, color);
}

// ShadePixel_Sphere and ShadePixel_Plane are created in the same way as ShadePixel_Sky

[Shader("node")]
[NodeId("ShadePixel", (uint)RayHit::Sphere)]
[NodeLaunch("thread")]
void ShadePixel_Sphere(ThreadNodeInputRecord<PixelRecord> input)
{
    const PixelRecord record = input.Get();

    WritePixel(record.pixel, ShadeSphere(record.ray, record.hitDistance));
}

[Shader("node")]
[NodeId("ShadePixel", (uint)RayHit::Plane)]
[NodeLaunch("thread")]
void ShadePixel_Plane(ThreadNodeInputRecord<PixelRecord> input)
{
    const PixelRecord record = input.Get();

    WritePixel(record.pixel, ShadePlane(record.ray, record.hitDistance));
}

// ================ "RenderScene" Node ================

[Shader("node")]
[NodeLaunch("broadcasting")]
[NodeMaxDispatchGrid(512, 512, 1)]
[NumThreads(8, 8, 1)]
void RenderScene(
    uint2 dispatchThreadId : SV_DispatchThreadID,

    DispatchNodeInputRecord<RenderSceneRecord> inputRecord,

    // [Task 3 Solution]: Output declaration to the "ShadePixel" node array:
    // 
    // RenderScene uses 8x8 threads and every thread can emit a "PixelRecord",
    // thus we need to declare a maximum of 8 * 8 = 64 outputs.
    [MaxRecords(8 * 8)]
    // NodeArraySize is required when using node array with fixed size.
    // If not all the nodes in the node array are populated, you can use [AllowSparseNodes]
    // to allow "gaps" in your node array.
    // If the maximum size of such a sparse node array is not known, you can use [UnboundedSparseNodes]
    // instead of [NodeArraySize(...)].
    // See https://microsoft.github.io/DirectX-Specs/d3d/WorkGraphs.html#node-output-declaration for more details.
    [NodeArraySize(3)]
    [NodeId("ShadePixel")]
    // As we are targeting an array of nodes, we have to use NodeOutputArray instead of NodeOutput.
    // NodeOutputArray provides an []-operator, with which we can select the
    // node array index for each record allocation (see below).
    // Similarly, for EmptyNodeOutput, there is also EmptyNodeOutputArray, if you do not want to pass any record data.
    NodeOutputArray<PixelRecord> output)
{
    // Scale dispatchThreadId by shading rate,
    // as every sample (i.e., every thread) can cover multiple pixel.
    const uint2 pixel = dispatchThreadId * SHADING_RATE;

    // Check if pixel is still within the output texture region.
    const bool hasOutput = all(pixel < RenderSize);

    Ray    ray;
    RayHit hit;

    // Trace ray into scene (if required).
    if (hasOutput) {
        ray = GetCameraRay(pixel);
        hit = TraceRay(ray);
    }

    // [Task 4 Solution]: Output a record to the "ShadePixel" node array with
    //                    hit.material being used as the index into this array:
    //
    // Request a per-thread record (if pixel is still on screen).
    // The material index of the hit object (or sky) is used as the index into
    // the "ShadePixel" node array (see nodes below).
    ThreadNodeOutputRecords<PixelRecord> outputRecord =
        output[(uint)hit.material].GetThreadNodeOutputRecords(hasOutput);

    if (hasOutput) {
        // Store all information required for shading the pixel into the record.
        outputRecord.Get().pixel       = pixel;
        outputRecord.Get().ray         = ray;
        outputRecord.Get().hitDistance = hit.distance;
    }

    // Mark records as complete and send it off.
    outputRecord.OutputComplete();
}

// ==================== Entry Node ====================
// The entry node below is invoked when dispatching the graph and launches
// the "RenderScene" node with one thread per sample.

[Shader("node")]
[NodeIsProgramEntry]
[NodeLaunch("thread")]
void Entry(
    [MaxRecords(1)]
    [NodeId("RenderScene")]
    NodeOutput<RenderSceneRecord> output)
{
    ThreadNodeOutputRecords<RenderSceneRecord> outputRecord =
        output.GetThreadNodeOutputRecords(1);

    // RenderScene uses a 8x8 thread group with one samples per thread.
    // Samples can cover multiple pixels (see note on SHADING_RATE above).
    const uint pixelsPerThreadGroup = 8 * SHADING_RATE;
    outputRecord.Get().dispatchGrid = (uint2(RenderSize) + pixelsPerThreadGroup - 1) / pixelsPerThreadGroup;

    outputRecord.OutputComplete();
}