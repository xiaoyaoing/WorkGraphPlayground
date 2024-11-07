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

#include <chrono>

#include "Device.h"
#include "ShaderCompiler.h"
#include "Swapchain.h"
#include "Window.h"
#include "WorkGraph.h"

class Application {
public:
    struct Options {
        std::wstring  title        = L"Work Graph Playground";
        std::uint32_t windowWidth  = 1280;
        std::uint32_t windowHeight = 720;

        bool forceWarpAdapter         = false;
        bool enableDebugLayer         = false;
        bool enableGpuValidationLayer = false;
    };

    Application(const Options& options);
    ~Application();

    void Run();

    static std::span<const WorkGraph::WorkGraphTutorial> GetTutorials();

private:
    void OnRender(ID3D12GraphicsCommandList10* commandList, const Swapchain::RenderTarget& renderTarget);
    void OnRenderUserInterface(ID3D12GraphicsCommandList10* commandList, const Swapchain::RenderTarget& renderTarget);
    void OnResize(std::uint32_t width, std::uint32_t height);

    void CreateImGuiContext();
    void DestroyImGuiContext();

    void CreateWorkGraphRootSignature();
    // Creates work graph. Returns if creation was successful
    bool CreateWorkGraph();

    // Util methods for shader resources
    void CreateResourceDescriptorHeaps();
    void CreateWritableBackbuffer(std::uint32_t width, std::uint32_t height);
    void CreateScratchBuffer();
    void CreatePersistentScratchBuffer();
    void ClearShaderResources(ID3D12GraphicsCommandList10* commandList);

    void CreateFontBuffer();

    std::unique_ptr<Window>    window_;
    std::unique_ptr<Device>    device_;
    std::unique_ptr<Swapchain> swapchain_;

    bool vsync_ = true;

    // Descriptor heap for ImGui
    ComPtr<ID3D12DescriptorHeap> uiDescriptorHeap_;

    // Descriptor heaps for shader resources
    ComPtr<ID3D12DescriptorHeap> clearDescriptorHeap_;
    ComPtr<ID3D12DescriptorHeap> resourceDescriptorHeap_;

    // Shader resources
    ComPtr<ID3D12Resource> writableBackbuffer_;
    ComPtr<ID3D12Resource> scratchBuffer_;
    ComPtr<ID3D12Resource> persistentScratchBuffer_;

    // Buffer resource containing font atlas
    ComPtr<ID3D12Resource> fontBuffer_;

    // Clear persistent scratch buffer after work graph switch
    bool clearPersistentScratchBuffer_ = true;

    // Timeout to show compilation error message
    std::chrono::high_resolution_clock::time_point errorMessageEndTime_ = std::chrono::high_resolution_clock::now();
    // Start time of current tutorial. Delta to current time is available in the shader as "Time"
    std::chrono::high_resolution_clock::time_point startTime_           = std::chrono::high_resolution_clock::now();

    // Work Graph resources
    ShaderCompiler              shaderCompiler_;
    ComPtr<ID3D12RootSignature> workGraphRootSignature_;
    std::uint32_t               workGraphTutorialIndex_     = 0;
    bool                        workGraphUseSampleSolution_ = false;
    std::unique_ptr<WorkGraph>  workGraph_;
};