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

// In this tutorial, we're going to take a look at the data-flow aspect of work graphs.
// In particular, we're going to see how you can pass data (i.e., records) from a producer node to a consumer node.
//
// Our goal is to draw boxes with text in them on screen.
// The "PrintBox" node is already printing the box content. All you have to do is draw a rectangle around the text.
// Additionally, we're going to enclose all boxes with another, larger rectangle.
//
// Eventually, should create a work graph which looks like this:
//
//                         +-------+
//                         | Entry |
//                         +-------+
//                             |
//           +-----------------+-----------------+
//           v                 v                 v
//  +-----------------+   +----------+   +---------------+
//  | PrintHelloWorld |   | PrintBox |   | DrawRectangle |
//  +-----------------+   +----------+   +---------------+
//
//
// Task 1: Take a look a the "Entry" node below, and see how it's currently emitting records to the "PrintBox" node.
//         See how the "PrintBox" node is then reading such a record to print text on screen.
//         Follow the instructions below to also emit an empty record to the "PrintHelloWorld" node.
// Task 2: Create the record struct to draw a rectangle around all boxes.
//         Take a look at the prepared stub for the "DrawRectangle" node to see what data needs to be passed in the record.
// Task 3: Add your record struct as an input to the "DrawRectangle" node below and
//         complete the code in the node to draw a rectangle on screen.
// Task 4: Add a node output to the "Entry" node for "DrawRectangle" node with your newly created record struct.
//         For now, we only care about the boxes around the already existing text, thus each thread will emit a single record.
//         Set the [MaxRecords(...)] attribute for your accordingly.
// Task 5: Emit the record to the "DrawRectanlge" node from the "Entry" node.
// Task 6: Additionally, we now want to draw another rectangle around all of these boxes.
//         Update the [MaxRecords(...)] attribute of your node output and follow the instructions below
//         to emit a per-thread-group record.

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

struct RectangleRecord {
    int2 topleft;
    int2 bottomright;
    float3 color;
};

// [Task 2]: Define a struct for the "DrawRectangle" node here!

[Shader("node")]
[NodeIsProgramEntry]
[NodeLaunch("broadcasting")]
[NodeDispatchGrid(1, 1, 1)]
[NumThreads(4, 1, 1)]
void Entry(
    // For this tutorial, the entry node uses a "broadcasting" node launch,
    // which in this case is equivalent to calling a compute shader with Dispatch(1, 1, 1).
    // We'll cover the different node launches in more detail in the next tutorial.
    // As this behaves like a compute shader, we can also use the SV_DispatchThreadID and
    // SV_GroupThreadID semantics to get the position of our thread in the dispatch/thread group.
    // In broadcasting mode, a node launches NodeDispatchGrid.x * NodeDispatchGrid.y * NodeDispatchGrid.z thread
    // groups. Here we have 1 thread-group. Each thread group has NumThreads.x * NumThreads.y * NumThreads.z threads. Here each thread group has 4 threads.
    uint2 dispatchThreadId : SV_DispatchThreadID,
    uint2 groupThreadId    : SV_GroupThreadID,
    uint2 groupId          : SV_GroupID,

    // The [MaxRecords(1)] attribute specifies the maximum number of records that a thread-group
    // will emit/send to a specific target node.
    // In this case, the entire thread group will only emit a single record. See [Task 1] for more details.
    [MaxRecords(1)]
    // As we have not specified a [NodeId(...)] attribute for the PrintHelloWorld node (see function definition below), its NodeId defaults to [NodeId("PrintHelloWorld", 0)].
    //
    // "PrintHelloWorld" function does not have any input records, thus we must use the "EmptyNodeOutput" to
    // declare the output.
    EmptyNodeOutput PrintHelloWorld,

    // In this tutorial, every thread of our thread group can emit a record to the "PrintBox" node.
    // As we have 4 threads in our thread group, we set this limit to 4.
    // We know that dispatch-thread (1, 0) does not actually emit a record and we only launch one group.
    // Therefore, we could also set this to 3.
    // But imagine you want to increase the [NodeDispatchGrid(...)] dimensions above, to have more thread-groups.
    // Then all threads of those thread-groups might want to emit a record.
    [MaxRecords(4)]
    // Here we use the [NodeId(...)] attribute to explicitly set the target node ID.
    // Using an explicit target attribute allows us to name the output parameter however we like.
    // Here we call it boxOutput.
    [NodeId("PrintBox")]
    // "PrintBox" declares an input record of type "PrintBoxRecord" (see node declaration below),
    // thus we must specify a "NodeOutput" with a record of the same type.
    NodeOutput<PrintBoxRecord> boxOutput,

    [MaxRecords(4)]
    [NodeId("DrawRectangle")]
    NodeOutput<RectangleRecord> rectangleOutput
    // [Task 4]: Declare a new "NodeOutput" to the "DrawRectangle" node here using your newly created record struct from Task 2.
    //           Similar to the "boxOutput", we want every thread to be able to request a per-thread output record.
    //           Set the [MaxRecords(...)] attribute accordingly.
)
{
    // [Task 1]: Emit a single empty record to the "PrintHelloWorld" node.
    //           For non-empty records, you've seen how "GetThreadNodeOutputRecords" is used to request
    //           one or more records below.
    //           For empty outputs, the equivalent here is "ThreadIncrementOutputCount(in int recordCount)",
    //           which emits a set number of empty records.
    //           Keep in mind, that we only want to emit a single record per thread-group.
    //           Thus only one thread would have to increment the output count.
    //           Alternatively, you can use "GroupIncrementOutputCount", to increment the output count for
    //           the entire thread group.
    const bool hasHelloWorldOutput = !all(dispatchThreadId == int2(0, 0));
    PrintHelloWorld.ThreadIncrementOutputCount(hasHelloWorldOutput ? 1 : 0);
        

    

    // Question: Have a look at the implementation of "PrintHelloWorld". What would happen if we incremented the
    //           output count multiple times?

    // Box position for each thread.
    const int2 threadBoxPosition = InitialBoxPosition + dispatchThreadId * (BoxSize + BoxMargin);

    // For demonstration purposes, we skip the second box.
    const bool hasBoxOutput = !all(dispatchThreadId == int2(1, 0));

    // Here we request a single output record per thread (if hasBoxOutput is true) to the "PrintBox" node.
    // As these calls for requesting output records (or incrementing the output count for empty node outputs)
    // must be thread-group uniform, i.e., all threads in the thread group must call this function at the same time,
    // we cannot use normal controlflow like
    // if (hasBoxOutput) {
    //     ThreadNodeOutputRecords<PrintBoxRecord> boxOutputRecord =
    //         boxOutput.GetThreadNodeOutputRecords(1);
    //     ...
    // }
    // if the condition is non-uniform across all threads to skip requesting outputs for some threads.
    // Insteads, these threads can just request zero output records instead.
    ThreadNodeOutputRecords<PrintBoxRecord> boxOutputRecord =
        boxOutput.GetThreadNodeOutputRecords(hasBoxOutput ? 1 : 0);

    // Threads that did not request any outputs must not write to the "boxOutputRecord" object.
    if (hasBoxOutput) {
        // Here we get the 0-th output record in the "boxOutputRecord" object and store our data to it.
        // If we called GetThreadNodeOutputRecords with more than one record (e.g., GetThreadNodeOutputRecords(2)),
        // we can then call "Get(...)" with different indices to write all these records.
        // If we only have a single record, we can also call "Get()" without any arguments to always get the 0-th record.
        boxOutputRecord.Get(0).topLeft = threadBoxPosition;
        // Alternatively, we can also use the []-operator to access the records.
        // Future HLSL version may also support a "->" operator for accessing records.
        boxOutputRecord[0].index       = dispatchThreadId;
    }

    // We are done writing our records and thus can send them off to be processed using the "OutputComplete" method.
    // Calls to this method must again be thread-group-uniform, thus must also be called by threads that did not
    // request any output records.
    boxOutputRecord.OutputComplete();

    // [Task 5]: Similar to the "boxOutputRecord" above, request a single per-thread record from your NodeOutput<...>.
    //           Again, we want to skip the second box, thus you can again use "hasBoxOutput" to selectively request
    //           zero records for the second thread.
    //           Write all required data to your record. You can use the "BoxSize" constant above to correctly size your rectangle.
    //           Don't forget to call "OutputComplete()" after writing the data to your record.

    const bool hasRectangleOutput = true; 
    ThreadNodeOutputRecords<RectangleRecord> rectangleOutputRecord = rectangleOutput.GetThreadNodeOutputRecords(hasRectangleOutput ? 1 : 0);
    if (hasRectangleOutput) {
        if(all(dispatchThreadId == int2(1, 0))) {
            rectangleOutputRecord.Get(0).topleft = InitialBoxPosition - int2(BoxMargin, BoxMargin);
            rectangleOutputRecord.Get(0).bottomright = InitialBoxPosition + int2(4 * (BoxSize.x + BoxMargin), BoxSize.y + BoxMargin) ;
            rectangleOutputRecord.Get(0).color = float3(1, 0, 0);
        }
        else {
            rectangleOutputRecord.Get(0).topleft = threadBoxPosition;
            rectangleOutputRecord.Get(0).bottomright = threadBoxPosition + BoxSize;
            rectangleOutputRecord.Get(0).color = float3(0, 0,0);
        }
    }
    rectangleOutputRecord.OutputComplete();

    // [Task 6]: Now we want to emit another record to "DrawRectangle", that draws a rectangle around all of our boxes.
    //           Start by adjusting the "[MaxRecords(...)]" attribute for the output to "DrawRectangle".
    //           As we need this rectangle to enclose all of the boxes emitted above, multiple thread must work together
    //           to create the record for this new rectangle.
    //           In particular, we know:
    //            - Thread (0, 0) emitted the record for the most top-left box.
    //            - Thread (3, 0) emitted the record for the most bottom-right box.
    //           Thus, we need a record that all threads of this thread group can access together.
    //           Use "GetGroupNodeOutputRecords" to get such a shared GroupNodeOutputRecords<...> object.
    //           Write the data to this record and don't forget to call "OutputComplete()" at the end.
}

[Shader("node")]
[NodeLaunch("thread")]
void PrintHelloWorld(
    // This node does not declare any input record, thus there's nothing to see here.
)
{
    // Print a "Hello World!" message above all the boxes.
    Cursor cursor = Cursor(InitialBoxPosition);
    cursor.Up(2);
    Print(cursor, "Hello World!");
}

[Shader("node")]
[NodeLaunch("thread")]
void PrintBox(
    // "PrintBox" uses the "thread" node launch (more on these in the next tutorial), thus, if we want to declare
    // an input record to this node, we must use the "ThreadNodeInputRecord" type with our desired record struct.
    ThreadNodeInputRecord<PrintBoxRecord> inputRecord

    // If our node were to also output any records to other nodes, then we could declare them here
    // in the same way as we've seen with the "Entry" node.
)
{
    // For easier access to members of the input record struct, we fetch the input record
    // using the ".Get()" function and store it to a local variable.
    const PrintBoxRecord record = inputRecord.Get();

    // Offset the cursor inside the box & print "Box(x, y)"
    Cursor cursor = Cursor(record.topLeft + BoxCursorOffset);
    Print(cursor, "Box (");
    // As we stored the input record to "record", we can directly access members of the
    // PrintBoxRecord from it.
    // Alternatively, we can also write "inputRecord.Get().index.x".
    // Future HLSL versions might also support a "->" operator, thus we can then write "inputRecord->index.x".
    PrintInt(cursor, record.index.x);
    Print(cursor, ", ");
    PrintInt(cursor, record.index.y);
    Print(cursor, ")");
}

[Shader("node")]
[NodeLaunch("thread")]
void DrawRectangle(
    // [Task 3]: Declare a node input for the "DrawRectangle" node with your new struct defined in Task 2 here.
    //           Similar to "PrintBox", "DrawRectangle" also uses the "thread" node launch,
    //           thus you must declare your input with "ThreadNodeInputRecord".
    ThreadNodeInputRecord<RectangleRecord> inputRecord
)
{
    // [Task 3]: Use the DrawRect function provided in Common.h to draw a rectanle on screen.
    // Use the data of your input record to pass it as arguments to the DrawRectFunction.
    // DrawRect(...);
    const RectangleRecord record = inputRecord.Get();
    DrawRect(record.topleft, record.bottomright, 1, record.color);
}

