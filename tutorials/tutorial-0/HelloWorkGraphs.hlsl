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

// Welcome to the first Work Graphs tutorial: Hello Work Graphs!
// In this tutorial, you familiarize youself with the "Work Graph Playground" application
// and see your first work graph in action.
// 
// The Work Graph Playground app supports "hot-reloading". That means 
// whenever you save any of the tutorial shader files, the playgroud app automatically recompiles the shaders and rebuilds the work graph.
// This will accellerate you on your Work Graphs learning curve!
//
// Now, follow the tutorial below to see this in action.

// This attribute lets us turn any void function into a Work Graphs node.
[Shader("node")]
// Each tutorial uses one work graph. In all our tutorials, we call the work graph entry nodes consistently "Entry".
// The CPU-side of the Work Graph Playground invokes the "Entry" node one time each frame.
// In all our tutorials, the CPU always passes a single empty input record to "Entry".
// Peek into WorkGraph::Dispatch in WorkGraph.cpp for more details on launching Work Graphs.
// Mark the node as entry node by "NodeIsProgramEntry" so it can be launched.
[NodeIsProgramEntry]
// We only need a single thread for now, so we use the "thread" launch mode.
// Other launch mode types are discussed in more detail in tutorial-2.
[NodeLaunch("thread")]
// In Work Graphs, nodes are identified by "node ids". A "Node id" consist of a node name and an optional array index.
// If you skip the array index, it is set to zero. If you skip the NodeId attribute, it defaults to the function name.
[NodeId("Entry", 0)]
// The NodeId-attribute, however, deflates its full potential in the context of node-arrays, as detailed in tutorial-3.
void EntryFunction(
    // Here in tutorial-0, the Entry node may invoke a second node and thus declares
    // an output record to the "Worker" node.    
    [MaxRecords(1)]                 // How many outputs? (here 1 output)
    [NodeId("Worker")]              // To what output node (here "Worker" is node id, we wish to launch). It is implemented by function WorkerFunction below).
    EmptyNodeOutput nodeOutput      // What is the record we send to the "Worker" node (here it is empty, there we use the EmptyNodeOutput object).
                                    // More on records in tutorial-1.
    )
{
    // To give visual feedback on what our work graph here in tutorial-0 is doing, we provide a small set of utility functions
    // for printing text onscreen.
    // See Common.h for more details.
    // For now, we print a small welcome message to the center of the screen.

    // Position cursor in center of screen.
    Cursor cursor = Cursor(RenderSize / 2, 2, float3(0,.5,1));        
    cursor.Up(3);

    // Print welcome message
    PrintCentered(cursor, "Hello Work Graphs!");
    cursor.Newline();
    cursor.Newline();
    PrintCentered(cursor, "Open");
    cursor.Newline();
    cursor.SetSize(3);
    cursor.SetColor(float3(1,.5,0));
    PrintCentered(cursor, "tutorials/tutorial-0/HelloWorkGraphs.hlsl");
    cursor.Newline();
    cursor.SetSize(2);
    cursor.SetColor(float3(0,.5,1));
    PrintCentered(cursor, "to start this tutorial");

    // [Task 1]
    // With the playground application running, uncomment the following line and save this file.

    nodeOutput.ThreadIncrementOutputCount(1); /* <-- uncomment me */

    // This line invokes the "Worker" node below one single time and you should see a second message appearing on sceen.
    // Edit the "Worker" function below to print a personalized hello-world message.
}

// This function contains the code of the Worker node.
[Shader("node")]
[NodeId("Worker", 0)]
[NodeLaunch("thread")]
void WorkerFunction()
{
    // Position cursor in center of screen.
    Cursor cursor = Cursor(RenderSize / 2, 2, float3(0, .5, 1));
    // Move cursor underneath first message
    cursor.Down(6);
    
    // [Task 2]
    // Edit the hello-world message here.
    // Save the file again and see the updated text onscreen.
    PrintCentered(cursor, "Hello <your name> from the \"Worker\" node!");
    
    // Congratulations, you've successfully completed tutorial-0!
    // To move on to the next tutorial, open the "Tutorials" menu on the top-left of the playground application and select "Tutorial 1: Records".
}
