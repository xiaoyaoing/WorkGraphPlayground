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

// In this tutorial, we're going to take a look at all the different options for launching nodes in a work graph.
// Work graphs replaces the concepts of draws (e.g., DrawInstanced, DrawIndexedInstances) and
// dispatches (e.g., Dispatch, DispatchRays) with records and node launches.
// Each record invokes a node and the node can choose from one of three launch modes:
//
// "broadcasting":
//   A broadcasting node is - on the surface - very similar to a compute shader:
//   Each record invokes a 3D grid of thread groups, with every thread group consisting of a 3D grid of threads.
//   You specify the size of the thread group with the [NumThreads(x, y, z)] attribute.
//   You can set the dispatch size (i.e., size of the thread-group grid) either statically using the
//   [NodeDispatchGrid(x, y, z)] attribute, or dynamically as part of the node input record.
//   We'll take a look at the latter part in Task 1.
//
// "thread":
//   Each record invokes a single thread, but unlike compute shaders or broadcasting nodes with [NumThreads(1, 1, 1)],
//   the work graphs runtime can combine multiple records and process them in a single thread group. Thus, the work 
//   graph runtime can then better leverage the available GPU resources.
//   Thread launches are ideal for single-threaded workloads (e.g., our Print functions).
//   You have already seen thread node launches in action in tutorial-0 and tutorial-1.
//
// "coalescing":
//   Unlike "broadcasting" or "thread" nodes, "coalescing" nodes can accept more than one input record:
//   A set of one or more input records invokes a single thread group. The size of the thread group is again denoted
//   by the [NumThreads(x, y, z)] attribute.
//   The maximum number of input records is declared using the [MaxRecords(...)] attribute. This happens in the same way as
//   we declare the output limits of a node. We've done this already in tutorial-1.
//   That said, a limit of, say, [MaxRecords(5)] only guarantees that the coalescing node is invoked with one to five records.
//   However, it does not mean that the input will always contain five records.
//   The actual number of input records present can be queried with the "Count()" method of the "GroupNodeInputRecords" object.
//   In this tutorial, we'll use a coalescing node to combine two rectangles into a single one if they share a vertical edge.
//
// See https://microsoft.github.io/DirectX-Specs/d3d/WorkGraphs.html#node-types for more details on all the launch modes.
// In our Work Graph Playground, we skip the experimental "mesh" launch mode. If you're interested,
// you can find more details on mesh nodes in Work Graphs here: https://gpuopen.com/learn/work_graphs_mesh_nodes.
//
// In tutorial-1, we declared inputs to our thread-launch nodes using the "ThreadNodeInputRecord" object.
// Node with the "broadcasting" and "coalescing" attribute use "DispatchNodeInputRecord" and "GroupNodeInputRecords", respectively.
// See https://microsoft.github.io/DirectX-Specs/d3d/WorkGraphs.html#node-input-declaration for details.
//
// In this assignments, we are again going to draw rectangles, but this time, instead of just drawing the outline,
// we also going to fill the rectangle. This is an ideal use-case for broadcasting nodes: we require as many threads as pixels 
// to efficiently fill large areas. 
// Additionally, we're going to demonstrate the capabilities of coalescing nodes, by combining two neighboring rectangles
// into a single one, if they share a vertical edge.
// The resulting graph for this tutorial will be as follows:
//
//             +----------------------------+
//             | NodeLaunch("broadcasting") |
//             |         Entry              |
//             +----------------------------+
//                           |
//            +--------------+--------------+
//            v                             v
// +----------------------+    +--------------------------+
// | NodeLaunch("thread") |    | NodeLaunch("coalescing") |
// |      PrintLabel      |    |      MergeRectangle      |
// +----------------------+    +--------------------------+
//                                          |
//                                          v
//                            +----------------------------+
//                            | NodeLaunch("broadcasting") |
//                            |       FillRectangle        |
//                            +----------------------------+
//
// Task 1: Have a look at the "FillRectangle" node below. It is currently using a fixed dispatch grid set by the
//         [NodeDispatchGrid(...)] attribute, thus all rectangles have the same size.
//         As the GetRectanglePositionAndSize helper computes an individual position and size for every rectangle,
//         we need to change this to a dynamic dispatch grid set by the input record.
//         Start by adding variables for the dispatch grid and rectangle size in the "RectangleRecord" struct.
//         Next, change the [NodeDispatchGrid(...)] attribute of the "FillRectangle" to a [NodeMaxDispatchGrid(...)]
//         and update the dispatch size limit in the x dimension.
//         Lastly, set the dispatch grid and rectangle size for the rectangle records in the "Entry" node.
//         Once you're done, the rectangles should now cover a continuous horizontal rectangle.
// Task 2: Change the "rectangleOutput" of the "Entry" node to target the "MergeRectangle" coalescing node.
//         The "MergeRectangle" takes one to two rectangles and we'll later use this functionality to combine
//         rectangles if they share an edge. In this task, you are going to implement the fallback path and
//         passthrough all incoming records to the "FillRectangle" node.
//         Once you're done, everything should still look the same.
// Task 3: Complete the implementation of the "MergeRectangle" node.
//         Complete the sub-call to the "ComputeCombinedRect" helper method.
//         If this helper returns "true", then you must emit a single record to the "FillRectangle" node.
//         Position and size of this rectangle are given by the "ComputeCombinedRect" helper.
//         For the color of this rectangle, you can re-use the color from any of the input records (e.g., record[0]).
//         Once you're done, you should now see the same area being filled, but this time with just three instead of five rectangles.
//         As five is not dividable by two, there's also one rectangle which could not be merged and is passed through as-is from
//         the "MergeRectangle" node to the "FillRectangle" node.
// Task 4: Increase the dispatch grid of the "Entry" node in x dimension to emit more rectangles.
//         You should now see the merged rectangles flickering, as the input to the coalescer node is non-deterministic
//         and depends on the timing of the different thread groups of the "Entry" node.
//         This step is omitted from the sample solution.

// Constants that define the layout and positioning of rectangles.
static const int  RectangleSize            = 48;
// Size increase with every rectangle.
static const int  RectangleSizeStep        = 4;
static const int2 RectangleCursorOffset    = int2(-8, -20);
static const int2 InitialRectanglePosition = int2(20, 60);

struct PrintLabelRecord {
    int2 topLeft;
    uint index;
};

// [Task 1]: 
//     Add a dispatch size and rectangle size member to the "RectangleRecord" struct.
//     The rectangle size will be in pixels, while the dispatch size will control how many thread
//     groups are dispatched. Each thread group will then cover an 8x8 pixel area.
//     Dispatch size (or dispatch grid) of a broadcasting node is specified in the record with the
//     "SV_DispatchGrid" semantic. The dispatch grid can be of type uint, uint2, uint3, uint16_t, uint16_t2 or uint16_t3.
//     See https://microsoft.github.io/DirectX-Specs/d3d/WorkGraphs.html#sv_dispatchgrid for more details.
//     In our case, we only need two dimensions, thus we recommend using uint2.
struct RectangleRecord {
    int2   topLeft;
    float4 color;
    uint2  dispatchGrid : SV_DispatchGrid;
    uint2  size;
};

// Helper function to compute the "position" and "size" for the rectangles from an "index".
void GetRectanglePositionAndSize(in uint index, out int2 position, out int2 size);

[Shader("node")]
[NodeIsProgramEntry]
[NodeLaunch("broadcasting")]
// [Task 4]: Increment the x dimension of the dispatch grid and observe the changes to the rectangle merging.
[NodeDispatchGrid(1, 1, 1)]
[NumThreads(5, 1, 1)]
void Entry(
    uint dispatchThreadId : SV_DispatchThreadID,

    [MaxRecords(5)]
    [NodeId("PrintLabel")]
    NodeOutput<PrintLabelRecord> printLabelOutput,

    [MaxRecords(5)]
    // [Task 2]: Change this output to target the "MergeRectangle" node.
    //           Hint: As "FillRectangle" and "MergeRectangle" share the same input node, your change should be rather small.
    [NodeId("MergeRectangle")]
    NodeOutput<RectangleRecord> rectangleOutput)
{
    // Rectangle position and size for each thread
    int2 threadRectanglePositon;
    int2 threadRectangleSize;
    GetRectanglePositionAndSize(dispatchThreadId, threadRectanglePositon, threadRectangleSize);

    ThreadNodeOutputRecords<PrintLabelRecord> printLabelRecord =
        printLabelOutput.GetThreadNodeOutputRecords(1);

    printLabelRecord.Get().topLeft = threadRectanglePositon;
    printLabelRecord.Get().index   = dispatchThreadId;

    printLabelRecord.OutputComplete();

    ThreadNodeOutputRecords<RectangleRecord> rectangleOutputRecord =
        rectangleOutput.GetThreadNodeOutputRecords(1);

    // [Task 1]: 
    //     Set the newly created dispatch size and rectangle size in the record.
    //     Rectangle size should be set to "threadRectangleSize" above.
    //     The unit of "threadRectangleSize" is in pixels, but the dispatch size is in thread groups.
    //     As each thread group covers an 8x8 pixel area, we need to divide the rectangle size by 8
    //     and round up to get the required dispatch size.
    //     You can use the "DivideAndRoundUp(int2 dividend, int2 divisor)" function in Common.h to perform this calculation.
    rectangleOutputRecord.Get().topLeft      = threadRectanglePositon;
    rectangleOutputRecord.Get().color        = UintToColor(dispatchThreadId);
    rectangleOutputRecord.Get().dispatchGrid = DivideAndRoundUp(threadRectangleSize, 8);
    rectangleOutputRecord.Get().size         = threadRectangleSize;
    rectangleOutputRecord.OutputComplete();
}

[Shader("node")]
[NodeLaunch("broadcasting")]
// [Task 1]: 
//     Change this from [NodeDispatchGrid(...)] to [NodeMaxDispatchGrid(...)] to allow for a dynamic grid size.
//     Together with the SV_DispatchGrid semantic in the "RectangleRecord" struct, this will
//     enable the "FillRectangle" to read it's dispatch grid dynamically from the input record.
//     The width of the rectangles increases linearly by "RectangleSizeStep" with each one.
//     We currently have 5 rectangles, but we want to increase this number later on.
//     Set the maximum dispatch grid to allow for at least 20 rectangles
//     (i.e., a rectangle which has a width of RectangleSize + 20 * RectangleSizeStep).
[NodeMaxDispatchGrid(8,8,1)]
[NumThreads(8, 8, 1)]
[NodeId("FillRectangle")]
void FillRectangleNode(
    DispatchNodeInputRecord<RectangleRecord> inputRecord,

    uint2 dispatchThreadId : SV_DispatchThreadID
)
{
    const RectangleRecord record = inputRecord.Get();

    const int2 pixel = record.topLeft + dispatchThreadId;
    // [Task 1]: 
    //    Each thread group can fill up to 8x8 pixels. If the rectangle size is not divisible by 8,
    //    we have to round up to ensure we launch enough thread groups.
    //    Thus, some thread groups may extend past the size of the rectangle.
    //    Add a check to test if "dispatchThreadId" is within the rectangle size (supplied by the input record).
    if (// Check if pixel is within bounds of render target.
        all(dispatchThreadId < record.size) &&
        all(pixel >= 0) && all(pixel < RenderSize)) {
        RenderTarget[pixel] = record.color;
    }
}

[Shader("node")]
[NodeLaunch("thread")]
[NodeId("PrintLabel")]
void PrintLabelNode(ThreadNodeInputRecord<PrintLabelRecord> inputRecord)
{
    const PrintLabelRecord record = inputRecord.Get();

    Cursor cursor = Cursor(record.topLeft + RectangleCursorOffset);
    Print(cursor, "|");
    PrintUint(cursor, record.index);
}

// Helper function to check if two rectangles share a vertical edge.
// Rectangles are defined by the position of their top-left corner and their size.
// If rectangles share a vertical edge, "topLeft" and "size" will contain the position and
// size of a rectangle covering both input rectangles.
bool ComputeCombinedRect(in int2 topLeft0, in int2 size0, in int2 topLeft1, in int2 size1, out int2 topLeft, out int2 size);

[Shader("node")]
[NodeLaunch("coalescing")]
[NumThreads(1, 1, 1)]
[NodeId("MergeRectangle")]
void MergeRectangleNode(
    [MaxRecords(2)]
    GroupNodeInputRecords<RectangleRecord> inputRecords,

    [MaxRecords(2)]
    [NodeId("FillRectangle")]
    NodeOutput<RectangleRecord> output
)
{
    // Only test of rectangles can be merged if two rectangles were passed.
    if (inputRecords.Count() == 2) {
        int2 topLeft, size;

        // [Task 3]: 
        //    Replace the parameters with the data from the input records.
        //    "inputRecords.Get(uint index)" or "inputRecords[uint index]" to access a specific input record.
        if (ComputeCombinedRect(/* in topLeft0: replace me! */ inputRecords.Get(0).topLeft,
                                /* in size0   : replace me! */ inputRecords.Get(0).size,
                                /* in topLeft1: replace me! */ inputRecords.Get(1).topLeft,
                                /* in size1   : replace me! */ inputRecords.Get(1).size,
                                /* out */ topLeft,
                                /* out */ size))
        {
            // [Task 3]: 
            //    Emit a single record to the "FillRectangle" node here.
            //    Use "topLeft" and "size" from above for this rectangle.
            //    Compute and set the dispatch size in the same way as you did in the "Entry" node.
            //    You can re-use the color from any of the input records, or compute a new color for
            //    the merged rectangle here.
            ThreadNodeOutputRecords<RectangleRecord> outputRecord =
                output.GetThreadNodeOutputRecords(1);
            outputRecord.Get().topLeft      = topLeft;
            outputRecord.Get().color        = inputRecords.Get(0).color;
            outputRecord.Get().dispatchGrid       = DivideAndRoundUp(size, 8);
            outputRecord.Get().size         = size;
            outputRecord.OutputComplete();

            // If we found two rectangles to merge, we can end the node here and thus
            // skip passing the input records through to the "FillRectangle" node.
            // Note: as we only have a single thread in our thread-group, such control flow
            //       is allowed, since all calls to output records are still thread-group uniform.
            return;
        }
    }

    int input_count = inputRecords.Count();
    ThreadNodeOutputRecords<RectangleRecord> outputRecord =
        output.GetThreadNodeOutputRecords(input_count);
    for(int i = 0;i<input_count;i++) {
        outputRecord.Get(i) = inputRecords.Get(i);
    }
    outputRecord.OutputComplete();

    // [Task 2]:
    //     Passthrough all incoming records to the "FillRectangle" output.
    //     Use "inputRecords.Count()" to get the number of input records,
    //     and thus also the number of required output records.
    //     Use ".Get(uint index)" or the "[]"-operator to get/set and input/output record.
}

// ================= Helper Functions =================

// Helper function to compute position and size for the rectangles.
void GetRectanglePositionAndSize(in uint index, out int2 position, out int2 size) {
    position = InitialRectanglePosition +
               int2(index, 0) * RectangleSize +
               int2(index * (index - 1) / 2, 0) * RectangleSizeStep;
    size     = RectangleSize.xx + int2(index, 0) * RectangleSizeStep;
}

// Helper function to check if two rectangles share a vertical edge.
bool ComputeCombinedRect(in int2 topLeft0, in int2 size0, in int2 topLeft1, in int2 size1, out int2 topLeft, out int2 size)
{
    const int2 topRight0 = topLeft0 + int2(size0.x, 0);
    const int2 topRight1 = topLeft1 + int2(size1.x, 0);

    // Compute top-left edge of combined rectangle.
    topLeft          = min(topLeft0, topLeft1);
    // Compute size of combined rectangle.
    const int  width = max(topRight0, topRight1).x - topLeft.x;
    size             = int2(width, size0.y);

    return
        // check if rectangles have same height.
        size0.y == size1.y &&
        // check if rectangles share a vertical edge.
        (width <= (size0.x + size1.x));
}
