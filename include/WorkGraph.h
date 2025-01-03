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

#include <span>

#include "Device.h"
#include "ShaderCompiler.h"

class WorkGraph {
public:
    struct WorkGraphTutorial {
        std::string name;
        std::string shaderFileName;
        // Filename for sample solution. Empty string means no solution is available.
        std::string solutionShaderFileName = "";
    };

    WorkGraph(const Device*        device,
              ShaderCompiler&      shaderCompiler,
              ID3D12RootSignature* rootSignature,
              std::uint32_t        tutorialIndex,
              bool                 sampleSolution);

    void Dispatch(ID3D12GraphicsCommandList10* commandList);

    std::uint32_t GetTutorialIndex() const;
    bool          IsSampleSolution() const;

private:
    std::uint32_t tutorialIndex_;
    bool          sampleSolution_;

    ComPtr<ID3D12StateObject> stateObject_;
    ComPtr<ID3D12Resource>    backingMemory_;
    D3D12_SET_PROGRAM_DESC    programDesc_ = {};
    std::uint32_t             entryPointIndex_;
};