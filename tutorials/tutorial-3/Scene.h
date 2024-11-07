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

// Emitting one record per pixel may cause low frame rates when using the
// WARP software adapter.
// SHADING_RATE defines the size of a sample in pixels.
// e.g., SHADING_RATE=2 means every sample will cover a 2x2 pixel area.
// If you're using WARP, we recommend a shading rate of 4 or higher.
#define SHADING_RATE 1

// Enable/disable animation of camera rotating around the scene
#define ANIMATION 1

// ================= Data Structs ================

// A struct define a raytracing ray.
struct Ray {
    // Origin of the ray.    
    float3 origin;
    // Unit length direction of the ray.
    // It is up to the user's responsibility to write normalized vectors to this member. 
    float3 direction;
};

// A struct that describes the result when a ray hit a surface.
struct RayHit {
    // Enum with the supported materials.
    enum Material : uint { Sky = 0, Sphere = 1, Plane = 2 };

    // Tells the material of the surface that the ray intersected.
    Material material;

    // Holds the distance from ray origin to the intersection.
    float    distance;
};

// =============== Scene Definition ==============
// Sphere setup.
static const float3 SphereCenter = float3(0.0, 1.0, 0.0);
static const float  SphereRadius = 1.0;
// Plane setup.
static const float3 PlaneNormal  = float3(0.0, 1.0, 0.0);
static const float  PlaneD       = 0.0;
static const float  PlaneSize    = 5;

// ============== Raytracing Methods =============

// Returns a camera ray to a given dispatchThreadId.
Ray GetCameraRay(in uint2 dispatchThreadId)
{
#if ANIMATION
    const float rotationAngle = Time;
#else
    const float rotationAngle = radians(45);
#endif
    const float3 cameraPosition  = float3(sin(rotationAngle) * 5, 2, cos(rotationAngle) * 5);
    // Camera looks at origin
    const float3 cameraDirection = normalize(-cameraPosition);

    const float3 forward = cameraDirection;
    const float3 right   = normalize(cross(forward, float3(0, 1, 0)));
    const float3 up      = normalize(cross(cameraDirection, right));

    // Normalize pixel position to [-1; 1].
    const float2 pixelPosition = ((dispatchThreadId / float2(RenderSize)) - 0.5f) * 2.f;
    const float  aspectRatio   = RenderSize.x / float(RenderSize.y);

    // Create camera ray.
    Ray ray;
    ray.origin    = cameraPosition;
    ray.direction = normalize(forward + right * pixelPosition.x * aspectRatio + up * pixelPosition.y);

    return ray;
}

RayHit TraceRay(in const Ray ray)
{
    // Hit distances for sphere and plane.
    float tSphere = 1.#INF;
    float tPlane  = 1.#INF;

    // Ray-Sphere intersection.
    {
        const float3 oc = ray.origin - SphereCenter;
        const float  a  = dot(ray.direction, ray.direction);
        const float  b  = 2.0 * dot(oc, ray.direction);
        const float  c  = dot(oc, oc) - SphereRadius * SphereRadius;
        const float  d  = b * b - 4.0 * a * c;

        if (d > 0.0) {
            const float t0 = (-b - sqrt(d)) / (2.0 * a);
            const float t1 = (-b + sqrt(d)) / (2.0 * a);
            tSphere        = min(t0, t1);
        }
    }

    // Ray-Plane intersection.
    {
        const float denom  = dot(PlaneNormal, ray.direction);
        if (abs(denom) > 1e-6) {
            tPlane = -(dot(ray.origin, PlaneNormal) + PlaneD) / denom;

            const float3 hitPosition = ray.origin + ray.direction * tPlane;

            // Limit plane to [-PlaneSize; PlaneSize] in xz-plane
            if (any(abs(hitPosition.xz) > (PlaneSize / 2.f))) {
                // Outside of plane dimensions
                tPlane = 1.#INF;
            }
        }
    }

    // Initialize fallback hit status.
    RayHit hit;
    hit.material = RayHit::Sky;
    hit.distance = 1.#INF;

    // Check if sphere distance is valid and closer than plane
    if (!isinf(tSphere) && (tSphere < tPlane)) {
        hit.material = RayHit::Sphere;
        hit.distance = tSphere;
    } else 
    // Check plane is valid
    if (!isinf(tPlane)) {
        hit.material = RayHit::Plane;
        hit.distance = tPlane;
    }
    // else the ray "hits" the sky. We already initialized that above.

    // Return the hit.
    return hit;
}

// ========== Material Shading Functions =========

// Set the "color" of a "pixel" given in zero-based integer coordinates.
// Covers SHADER_RATE pixels in x and y direction.
// Pixel must be a valid pixel, otherwise the behaviour is undefined.
void WritePixel(in const uint2 pixel, in const float4 color)
{
    for (uint y = 0; y < SHADING_RATE; ++y) {
        for (uint x = 0; x < SHADING_RATE; ++x) {
            const uint2 outputPixel = pixel + uint2(x, y);

            if (all(outputPixel < RenderSize)) {
                RenderTarget[outputPixel] = color;
            }
        }
    }
}

// Returns the color of the sky.
float4 ShadeSky(in const Ray ray)
{
    const float f = (ray.direction.y + 1.5) * 0.5;
    return float4(f * 0.4, f * 0.7, f * 1, 1);
}

// Returns the color of the sphere.
// Uses the "ray" and its "hitDistance" to determine the color.
float4 ShadeSphere(in const Ray ray, in const float hitDistance)
{
    const float3 hitPosition = ray.origin + ray.direction * hitDistance;
    const float3 normal      = normalize(hitPosition - SphereCenter);

    return float4(0.5 + normal * 0.5, 1);
}

// Returns the color of the plane.
// Uses the "ray" and its "hitDistance" to determine the color.
float4 ShadePlane(in const Ray ray, in const float hitDistance)
{
    const float3 hitPosition = ray.origin + ray.direction * hitDistance;

    const bool checkerboard = (int(hitPosition.x - PlaneSize) % 2) ^ (int(hitPosition.z - PlaneSize) % 2);

    return checkerboard ? float4(0.2, 0.2, 0.2, 1.0) : float4(0.8, 0.8, 0.8, 1.0);
}