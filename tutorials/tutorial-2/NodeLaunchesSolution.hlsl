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

struct RectangleRecord {
    // [Task 1 Solution]: SV_DispatchGrid denotes the size of the dispatch grid for the "FillRectangle" node.
    //                    When this record is used with other non-broadcasting nodes (e.g. "MergeRectangle"),
    //                    this semantic has no effect.
    uint2  dispatchGrid : SV_DispatchGrid;
    int2   topLeft;
    // [Task 1 Solution]: As "dispatchGrid" has thread-group granularity, i.e. in our case 8x8 pixels, we also need to
    //                    pass the actual rectangle size, in-case it does not evenly divide by 8.
    //                    See implementation of "FillRectangle" node below.
    int2   size;
    float4 color;
};

// Helper function to compute the "position" and "size" for the rectangles from an "index".
void GetRectanglePositionAndSize(in uint index, out int2 position, out int2 size);

[Shader("node")]
[NodeIsProgramEntry]
[NodeLaunch("broadcasting")]
// [Task 4]: Increment the x dimension of the dispatch grid and observe the changes to the rectangle merging.
//           This step is omitted from the sample solution to show a state closer to the start of the tutorial.
[NodeDispatchGrid(1, 1, 1)]
[NumThreads(5, 1, 1)]
void Entry(
    uint dispatchThreadId : SV_DispatchThreadID,

    [MaxRecords(5)]
    [NodeId("PrintLabel")]
    NodeOutput<PrintLabelRecord> printLabelOutput,

    [MaxRecords(5)]
    // [Task 2 Solution]:
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

    // [Task 1 Solution]:
    //     Each thread group of the "FillRectangle" node covers an 8x8 pixel area.
    //     Thus, we need to divide "threadRectangleSize" by 8 to get the number of thread groups required
    //     to fill the rectangle. As "threadRectangleSize" might not evenly divide by 8, we need to round up
    //     to ensure we dispatch enough thread groups.
    rectangleOutputRecord.Get().dispatchGrid = DivideAndRoundUp(threadRectangleSize, 8);
    rectangleOutputRecord.Get().topLeft      = threadRectanglePositon;
    rectangleOutputRecord.Get().size         = threadRectangleSize;
    rectangleOutputRecord.Get().color        = UintToColor(dispatchThreadId);

    rectangleOutputRecord.OutputComplete();
}

[Shader("node")]
[NodeLaunch("broadcasting")]
// [Task 1 Solution]:
//        6 thread groups for base-size rectangle (48x48)
//     + 10 thread groups (x8 = 80 pixels) to cover the size of the 20 th thread group (48 + 19 * 4)
[NodeMaxDispatchGrid(6 + 10, 6, 1)]
[NumThreads(8, 8, 1)]
[NodeId("FillRectangle")]
void FillRectangleNode(
    DispatchNodeInputRecord<RectangleRecord> inputRecord,

    uint2 dispatchThreadId : SV_DispatchThreadID
)
{
    const RectangleRecord record = inputRecord.Get();

    const int2 pixel = record.topLeft + dispatchThreadId;

    // [Task 1 Solution]:
    //     Add "all(dispatchThreadId < record.size)" to check if pixel is within the rectangle.
    if (// Check if pixel is still within rectangle.
        all(dispatchThreadId < record.size) &&
        // Check if pixel is within bounds of render target.
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
    if (inputRecords.Count() == 2) {
        int2 topLeft, size;

        // [Task 3 Solution]:
        if (ComputeCombinedRect(inputRecords.Get(0).topLeft,
                                inputRecords.Get(0).size,
                                inputRecords.Get(1).topLeft,
                                inputRecords.Get(1).size,
                                /* out */ topLeft,
                                /* out */ size))
        {
            // Emit a single "RectangleRecord" to "FillRectangle".
            ThreadNodeOutputRecords<RectangleRecord> outputRecord =
                output.GetThreadNodeOutputRecords(1);
            // Similar to "Entry" node, divide rectangle size by 8 and round up
            // to get the number of required thread groups to fill the rectangle.
            outputRecord.Get().dispatchGrid = DivideAndRoundUp(size, 8);
            outputRecord.Get().topLeft      = topLeft;
            outputRecord.Get().size         = size;
            // Passthrough color from input record [0] here.
            // This allows us to see which rectangle was passed to "MergeRectangle"
            // as input record [0], and which rectangle was passed as input record [1].
            outputRecord.Get().color        = inputRecords.Get(0).color;
            outputRecord.OutputComplete();
            return;
        }
    }

    // [Task 2 Solution]:
    //     Request one output record for each input record (inputRecords.Count())
    //     As the entire record, including the dispatch grid, has already been written
    //     in the "Entry" node, there's nothing to change/modify here.
    ThreadNodeOutputRecords<RectangleRecord> outputRecords =
        output.GetThreadNodeOutputRecords(inputRecords.Count());

    // Iterate over input records and pass them through to the output records.
    // As the entire record, including the dispatch grid, has already been written
    // in the "Entry" node, there's nothing to change/modify here.
    for (int i = 0; i < inputRecords.Count(); ++i) {
        outputRecords.Get(i) = inputRecords.Get(i);
    }

    outputRecords.OutputComplete();
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
