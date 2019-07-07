﻿// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
using System.Collections.Generic;
using System.Threading.Tasks;
using WebApp.Arm;
using WebApp.Config.Storage;
using WebApp.Models.Storage.Create;
using WebApp.Operations;

namespace WebApp.Code.Contract
{
    public interface IAssetRepoCoordinator
    {
        Task<List<string>> ListRepositories();

        Task<AssetRepository> GetRepository(string repoName);

        AssetRepository CreateRepository(AddAssetRepoBaseModel model);

        Task BeginRepositoryDeploymentAsync(AssetRepository repository, IAzureResourceProvider azureResourceProvider);

        Task<ProvisioningState> UpdateRepositoryFromDeploymentAsync(AssetRepository repository);

        Task BeginDeleteRepositoryAsync(AssetRepository repository);

        Task DeleteRepositoryResourcesAsync(AssetRepository repository);

        Task UpdateRepository(AssetRepository repository, string originalName = null);

        Task<bool> RemoveRepository(AssetRepository repository);
    }
}