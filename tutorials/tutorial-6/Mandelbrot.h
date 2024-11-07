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

#pragma once

// ====================== Config ======================

// Enable/disable zoom animation to pointOfInterest (see below).
#define ANIMATION 1

// Length of zoom animation in seconds.
static const float  animationLength = 4;
// Depth of zoom animation, i.e., how far to zoom into the fractal.
static const float  animationDepth  = 12;
// Point of interest for zoom animation.
static const float2 pointOfInterest = float2(-0.6512, 0.4795);

// Maximum number of Mandelbrot iterations to carry out.
static const int maxIteration = 256;

// Maximum area of Mandelbrot to draw.
static const float2 mandelbrotMin = float2(-2.00, -1.12);
static const float2 mandelbrotMax = float2(0.47, 1.12);

// ===================== Mandelbrot ====================

int GetPixelDwell(in const float2 pixel)
{
#if ANIMATION
    float t                = (Time % (2 * animationLength)) / animationLength;
    t                      = smoothstep(0, 1, (t > 1) ? 2 - t : t);
    const float zoomFactor = pow(2.0, t * -animationDepth);
#else
    const float zoomFactor = 1.f;
#endif

    float2 mandelMin   = pointOfInterest + (mandelbrotMin - pointOfInterest) * zoomFactor;
    float2 mandelMax   = pointOfInterest + (mandelbrotMax - pointOfInterest) * zoomFactor;
    float2 mandelDelta = mandelMax - mandelMin;
    float  mandelRatio = mandelDelta.x / mandelDelta.y;

    float  screenRatio = float(RenderSize.x) / RenderSize.y;
    float2 pos         = pixel;
    if (screenRatio > mandelRatio) {  // Screen is wider than Mandelbrot, adjust X (horizontal) center
        pos.x = pixel.x - (RenderSize.x - RenderSize.x * mandelRatio / screenRatio) * .5;
        pos *= mandelDelta.y / RenderSize.y;
    } else {  // Screen is taller than Mandelbrot, adjust Y (vertical) center
        pos.y = pixel.y - (RenderSize.y - RenderSize.y * screenRatio / mandelRatio) * .5;
        pos *= mandelDelta.x / RenderSize.x;
    }
    pos += mandelMin;

    float2 c = float2(0, 0);
    int    i = 0;
    for (; i < maxIteration && dot(c, c) <= 4; ++i) {
        c = pos + float2(c.x * c.x - c.y * c.y, 2 * c.x * c.y);
    }
    return i;
}

float3 Heatmap(float x)
{
    x         = clamp(x, 0.0f, 1.0f);
    float4 x1 = float4(1.0, x, x * x, x * x * x);  // 1 x x2 x3
    float2 x2 = x1.xy * x1.w * x;                  // x4 x5 x6 x7
    return float3(dot(x1, float4(+0.063861086f, +1.992659096f, -1.023901152f, -0.490832805f)) +
                      dot(x2, float2(+1.308442123f, -0.914547012f)),
                  dot(x1, float4(+0.049718590f, -0.791144343f, +2.892305078f, +0.811726816f)) +
                      dot(x2, float2(-4.686502417f, +2.717794514f)),
                  dot(x1, float4(+0.513275779f, +1.580255060f, -5.164414457f, +4.559573646f)) +
                      dot(x2, float2(-1.916810682f, +0.570638854f)));
}

float3 DwellToColor(int dwell)
{
    return Heatmap(pow(dwell / float(maxIteration), .35));
}