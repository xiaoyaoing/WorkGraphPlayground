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


//                         +-------+
//                         | Entry |
//                         +-------+
//                             |
//           +-----------------+-----------------+
//           v                 v                 v
//  +-----------------+   +----------+   +---------------+
//  | PrintHelloWorld |   | PrintBox |   | DrawRectangle |
//  +-----------------+   +----------+   +---------------+

// Constants that define layout and positioning of boxes.
static const int  BoxMargin          = 10;
static const int2 BoxSize            = int2(165, 20);
static const int2 BoxCursorOffset    = int2(5, 3);
static const int2 InitialBoxPosition = int2(BoxMargin * 2, 60);

// Record struct for the "PrintBox" node.
struct PrintBoxRecord {
    // Top-left pixel coordinate for a box.
    int2 topLeft;
    // Index to print inside the box. See "PrintBox" implementation below.
    int2 index;
};

// [Task 2 Solution]: Record struct to draw a rectangle on screen.
//                    See "DrawRectangle" node implementation below.
struct DrawRectangleRecord {
    // Pixel coordinate of top-left corner of rectangle.
    int2   topLeft;
    // Pixel coordinate of bottom-right corner of rectangle.
    int2   bottomRight;
    // Color of the rectangle.
    float3 color;
};

[Shader("node")]
[NodeIsProgramEntry]
[NodeLaunch("broadcasting")]
[NodeDispatchGrid(1, 1, 1)]
[NumThreads(4, 1, 1)]
void Entry(
    uint2 dispatchThreadId : SV_DispatchThreadID,
    uint2 groupThreadId    : SV_GroupThreadID,
    uint2 groupId          : SV_GroupID,
    [MaxRecords(1)]
    EmptyNodeOutput PrintHelloWorld,

    [MaxRecords(4)]
    [NodeId("PrintBox")]
    NodeOutput<PrintBoxRecord> boxOutput,

    // [Task 4 Solution]: 5 records: 4 records (one per box) and one record enclosing all boxes.
    [MaxRecords(5)]
    [NodeId("DrawRectangle")]
    NodeOutput<DrawRectangleRecord> rectangleOutput
)
{
    // [Task 1 Solution]:
    PrintHelloWorld.GroupIncrementOutputCount(1);

    // Box position for each thread.
    const int2 threadBoxPosition = InitialBoxPosition + dispatchThreadId * (BoxSize + BoxMargin);

    // For demonstration purposes, we skip the second box.
    const bool hasBoxOutput = !all(dispatchThreadId == int2(1, 0));

    ThreadNodeOutputRecords<PrintBoxRecord> boxOutputRecord =
        boxOutput.GetThreadNodeOutputRecords(hasBoxOutput ? 1 : 0);

    if (hasBoxOutput) {
        boxOutputRecord.Get(0).topLeft = threadBoxPosition;
        boxOutputRecord[0].index       = dispatchThreadId;
    }

    boxOutputRecord.OutputComplete();

    // [Task 5 Solution]:
    ThreadNodeOutputRecords<DrawRectangleRecord> threadRectangleRecord =
        rectangleOutput.GetThreadNodeOutputRecords(hasBoxOutput ? 1 : 0);

    if (hasBoxOutput) {
        threadRectangleRecord.Get().topLeft     = threadBoxPosition;
        threadRectangleRecord.Get().bottomRight = threadBoxPosition + BoxSize;
        threadRectangleRecord.Get().color       = float3(0, 0, 0);
    }

    threadRectangleRecord.OutputComplete();

    // [Task 6 Solution]:
    GroupNodeOutputRecords<DrawRectangleRecord> groupRectangleRecord =
        rectangleOutput.GetGroupNodeOutputRecords(1);

    // The first thread in the group wrote the record for the most top-left box,
    // thus only this thread must write the topLeft position of the shared rectangle record.
    if (groupThreadId.x == 0 && groupThreadId.y == 0) {
        groupRectangleRecord.Get().topLeft = threadBoxPosition - BoxMargin;
    }
    // Similarly, the last thread wrote the most bottom-right box record,
    // thus only this thread must write the bottomRight position of the shared rectangle record.
    if (groupThreadId.x == 3 && groupThreadId.y == 0) {
        groupRectangleRecord.Get().bottomRight = threadBoxPosition + BoxSize + BoxMargin;
    }

    // All threads jointly write the same color to the shared record.
    groupRectangleRecord.Get().color = float3(1, 0, 0);

    // All data has been written, send the shared group record.
    groupRectangleRecord.OutputComplete();
}

[Shader("node")]
[NodeLaunch("thread")]
void PrintHelloWorld()
{
    // Print a "Hello World!" message above all the boxes.
    Cursor cursor = Cursor(InitialBoxPosition);
    cursor.Up(2);
    Print(cursor, "Hello World!");
}

[Shader("node")]
[NodeLaunch("thread")]
void PrintBox(ThreadNodeInputRecord<PrintBoxRecord> inputRecord)
{
    const PrintBoxRecord record = inputRecord.Get();

    // Offset the cursor inside the box & print "Box(x, y)"
    Cursor cursor = Cursor(record.topLeft + BoxCursorOffset);
    Print(cursor, "Box (");
    PrintInt(cursor, record.index.x);
    Print(cursor, ", ");
    PrintInt(cursor, record.index.y);
    Print(cursor, ")");
}

[Shader("node")]
[NodeLaunch("thread")]
void DrawRectangle(
    // [Task 3 Solution]:
    ThreadNodeInputRecord<DrawRectangleRecord> inputRecord
)
{
    // [Task 3 Solution]:
    // We again store the input record to a local variable first...
    const DrawRectangleRecord record = inputRecord.Get();

    // ... and use the data contained in the record to draw a rectangle on screen.
    DrawRect(record.topLeft, record.bottomRight, 1, record.color);
}

