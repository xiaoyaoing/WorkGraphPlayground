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

// This tutorial teaches about Node Recursion, using fractals as an example.
// For the offical recursion spec, see https://microsoft.github.io/DirectX-Specs/d3d/WorkGraphs.html#recursion
// Remember: The only recursion (or cycles) allowed in Work Graphs is a Node creating records for itself.
// Thus, a configuration where a Node "A" creates work for a node "B" and "B" is creating work for "A" is not allowed.
// When a node has a NodeOutput to itself, the [NodeMaxRecursionDepth(n)] must be declared.
// Calling GetRemainingRecursionLevels() in the node returns the remaining available levels.

// To provide an example to learn and copy from, this tutorial provides code for drawing the Koch Snowflake fractal.
// The node "Snowflake" receives a "Line" record as input and splits it into 4 lines. When the recursion limit is reached, the line is drawn instead.
//
// Task 1: Try playing around with the maximum number of recursion levels of the "Snowflake" node.

// Task 2: Now, create a second fractal which works very similar to the given example: the Menger Sponge.
// Use a square as input, which splits into 8 smaller new squares, leaving the center of the square empty.

struct Line
{
    float2 a, b;
};

// [Task 2]: Declare a structure for the box.

[Shader("node")]
[NodeIsProgramEntry]
[NodeLaunch("thread")]
[NodeId("Entry")]
void EntryNode(
    [MaxRecords(3)]
    [NodeId("Snowflake")]
    NodeOutput<Line> snowflakeOutput
    // [Task 2]: Declare output for Menger Sponge
){
    const bool   stackVertical = RenderSize.x > RenderSize.y;
    const float  scale         = stackVertical? min(RenderSize.x * .225, RenderSize.y * .45) :
                                                min(RenderSize.x * .45, RenderSize.y * .225);
    // Draw Snowflake fractal.
    {
        const float2 snowflakeCenter = RenderSize * (stackVertical? float2(.25, .5) : float2(.5, .25));

        // Request three output records for the three sides of the initial equilateral triangle.
        ThreadNodeOutputRecords<Line> outputRecords =
            snowflakeOutput.GetThreadNodeOutputRecords(3);

        // Compute three vertices of the initial equilateral triangle.
        const float2 v0 = snowflakeCenter + scale * float2(0., -1.);
        const float2 v1 = snowflakeCenter + scale * float2(-sqrt(3) * .5, .5);
        const float2 v2 = snowflakeCenter + scale * float2(+sqrt(3) * .5, .5);

        // Create the initial equilateral triangle.
        outputRecords.Get(0).a = v0;
        outputRecords.Get(0).b = v1;

        outputRecords.Get(1).a = v1;
        outputRecords.Get(2).a = v2;

        outputRecords.Get(2).b = v0;
        outputRecords.Get(1).b = v2;

        outputRecords.OutputComplete();
    }

    // Draw Sponge fractal.
    {
        // The center of your fractal should be at spongeCenter
        const float2 spongeCenter = RenderSize * (stackVertical? float2(.75, .5) : float2(.5, .75));

        // [Task 2]: Emit your initial record(s) here to draw the Menger Sponge fractal.
    }
}

[Shader("node")]
[NodeLaunch("thread")]
// If a node declares a recursive output to itself (see "recursiveOutput" below),
// a "[NodeMaxRecursionDepth(...)]" is required to specify the maximum number of recursion levels.
// This is required, as each recursion level counts towards the total graph depth,
// and the runtime has to ensure that this depth does not exceed the limit of 32 nodes.
// We can use "GetRemainingRecursionLevels()" in the node function to query the remaining
// recursion levels, i.e., determine whether we can still request recursive output records.
[NodeMaxRecursionDepth(4)]
[NodeId("Snowflake")]
void SnowflakeNode(
    ThreadNodeInputRecord<Line> inputRecord,

    [MaxRecords(4)]
    [NodeId("Snowflake")]
    NodeOutput<Line> recursiveOutput
)
{
    const float2 a = inputRecord.Get().a;
    const float2 b = inputRecord.Get().b;

    // Check if we have reached the recursion limit.
    const bool hasOutput = GetRemainingRecursionLevels() != 0;

    // Each recursion level has a 4x amplification factor, as each line
    // splits into four new lines.
    ThreadNodeOutputRecords<Line> outputRecords =
        recursiveOutput.GetThreadNodeOutputRecords(hasOutput * 4);

    if (hasOutput) {
        // Perpendicular vector to current line segment.
        const float2 perp = float2(a.y - b.y, b.x - a.x) * sqrt(3) / 6;

        // Compute vertices for the four new line segments:
        //
        //             v2
        //            /  \
        //           /    \
        // v0 ---- v1      v3 ---- v4
        const float2 v0 = a;
        const float2 v1 = lerp(a, b, 1./3.);
        const float2 v2 = lerp(a, b, .5) + perp;
        const float2 v3 = lerp(a, b, 2./3.);
        const float2 v4 = b;

        outputRecords.Get(0).a = v0;
        outputRecords.Get(0).b = v1;

        outputRecords.Get(1).a = v1;
        outputRecords.Get(1).b = v2;

        outputRecords.Get(2).a = v2;
        outputRecords.Get(2).b = v3;

        outputRecords.Get(3).a = v3;
        outputRecords.Get(3).b = v4;
    } else {
        // We've reached the recursion limit, thus we draw the current line segment
        // to the output.
        DrawLine(a, b);
    }

    outputRecords.OutputComplete();
}

// [Task 2]: Create a node that either subdivides a input Box into eight boxes or
//           draws the input Box. Use FillRect from Common.h to draw the box.