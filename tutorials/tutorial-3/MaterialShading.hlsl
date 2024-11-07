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

// ================ Start of tutorial =================

// In this tutorial, we'll look a node arrays, using per-pixel material shading as an example.
// Material shading is commonly used with visibility buffers. A prominent example for this would be Unreal Engine's Nanite.
// The input is a (different) material ID for every pixel and set of shading functions, which calculate the pixel color
// based on the material ID and some other parameters.
// For this tutorial, we use raytracing to render a small scene with three different materials: the sky, a sphere, and a plane.
// You can find the raytracing code and material shading function in "Scene.h".

// Task 0: Start by familiarizing yourself with the existing code.
//         Have a look at the "RenderScene" and see how it is launched from the "Entry" node at the bottom of the file.
//         All of this should be familiar by now - if not, maybe have a look at the previous tutorials again.
// Task 1: Have a look at the data required to shade a pixel (or sample) (e.g., pixel coordinate)
//         Start by declaring a record for shading a single pixel below.
// Task 2: Declare a node for each of the three different materials. See details below.
//         All of these nodes must use the same [NodeLaunch(...)] parameter and use the same input record.
// Task 3: Declare an output to your node array in the "RenderScene" node.
// Task 4: For each thread, create and send a record to your node array with the correct node array index based on the ray tracing result.
//         Fill your record with all the data needed to shade the material.
//
// The resulting graph will then look like this:
//
// +-------+         +-------------+         +------------------------+
// | Entry |-------->| RenderScene |-------->|     ShadePixel[3]      |
// +-------+         +-------------+         |========================|
//                                           | Nodes in NodeArray:    |
//                                           | [0]: ShadePixel_Sky    |
//                                           | [1]: ShadePixel_Sphere |
//                                           | [2]: ShadePixel_Plane  |
//                                           +------------------------+

// [Task 1]: Define your record struct to shade each pixel here.

// [Task 2]: Declare your material shading nodes here, using the record you just defined as an input.
//           Revisit tutorial-2 and choose a fitting node launch mode for shading a pixel.
//           You'll need three different nodes for each of the different materials.
//           Use the [NodeId(...)] attribute to tie all of these nodes together to a single node array.
//           Tipp: You can use [NodeId("...", (uint)RayHit::Material::...)] to use the "Material" enum instead of hard-coded values.

[Shader("node")]
[NodeLaunch("broadcasting")]
[NodeMaxDispatchGrid(512, 512, 1)]
[NumThreads(8, 8, 1)]
void RenderScene(
    uint2 dispatchThreadId : SV_DispatchThreadID,

    DispatchNodeInputRecord<RenderSceneRecord> inputRecord

    // [Task 3]: Declare the output to your newly created node array here.
    //           Revisit tutorial-1 for a refresh on node outputs and determine the correct [MaxRecords(...)] attribute.
    //           As you're now using a node array, you'll need to use NodeOutputArray<...> instead of NodeOutput<...>.
    //           Additionally, you need to specify the node array size using the [NodeArraySize(...)] attribute.
    //           This is for the runtime to check that the entire node array is actually present in the graph.
    //           See https://microsoft.github.io/DirectX-Specs/d3d/WorkGraphs.html#node-output-declaration for more details.
)
{
    // Scale dispatchThreadId by shading rate,
    // as every sample (i.e., every thread) can cover multiple pixel.
    const uint2 pixel = dispatchThreadId * SHADING_RATE;

    if (any(pixel >= RenderSize)) {
        // Early exit if pixel is outside the render target.
        // !! Keep in mind that any calls to GetThreadNodeOutputRecords or GetGroupNodeOutputRecords
        //    need to be thread-group uniform, i.e., reached by every thread in the threadgroup !!
        return;
    }

    // GetCameraRay compute ray origin and direction for a primary ray.
    const Ray    ray = GetCameraRay(pixel);
    // TraceRay computes ray intersections with the scene and returns
    // hit distance and material ID in the "RayHit" struct
    const RayHit hit = TraceRay(ray);

    float4 color = float4(0, 0, 0, 1);

    // Here we call different shading functions based on the raytracing results.
    // This will lead to divergent code flow on the GPU and can slow down shading if
    // lots of different materials, with varying resource requirements are used.
    // In this tutorial, we want to replace this swtich-case statement with a
    // work graph node array, such that every material is processed by a different shader.
    // Each node (material shader) then only allocated the resources it actually requires.
    //
    // Here we're only shading three different materials: the sky, a sphere and the plane.
    switch(hit.material) {
        case RayHit::Sky:
            color = ShadeSky(ray);
            break;
        case RayHit::Sphere:
            color = ShadeSphere(ray, hit.distance);
            break;
        case RayHit::Plane:
            color = ShadePlane(ray, hit.distance);
            break;
        default:
            break;
    }

    // WritePixel stores the color to all pixels in a sample (see SHADING_RATE above).
    // As Work Graphs does not offer a return-path to the producer node, you task it to move it
    // to each of the material shading nodes.
    WritePixel(pixel, color);

    // [Task 4]: Emit the output to your node array here.
    //           NodeOutputArray provides a []-operator to select the array index for each output request with
    //           output[index].Get{Thread|Group}NodeOutputRecords(...)
    //           Make sure to call this in a thread-group uniform way and write your data to the record.
    //           You can then remove the existing material shading code above.
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