using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Hospital_API.DTOs;
using Hospital_API.Models;
using Hospital_API.Interfaces;
using Microsoft.Extensions.Caching.Distributed;

namespace Hospital_API.Services
{
    public class BranchService : IBranchService
    {
        private const string BranchListCacheKey = "branch:all";
        private static readonly DistributedCacheEntryOptions CacheOptions = new()
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5)
        };

        private readonly IBranchRepository _repository;
        private readonly IDistributedCache _cache;

        public BranchService(IBranchRepository repository, IDistributedCache cache)
        {
            _repository = repository;
            _cache = cache;
        }

        public async Task<IEnumerable<BranchDTO>> GetAllAsync()
        {
            var cachedBranches = await _cache.GetStringAsync(BranchListCacheKey);
            if (!string.IsNullOrWhiteSpace(cachedBranches))
            {
                return JsonSerializer.Deserialize<List<BranchDTO>>(cachedBranches) ?? [];
            }

            var branches = await _repository.GetAllAsync();
            var branchDtos = branches.Select(MapToDTO).ToList();

            await _cache.SetStringAsync(
                BranchListCacheKey,
                JsonSerializer.Serialize(branchDtos),
                CacheOptions);

            return branchDtos;
        }

        public async Task<BranchDTO> GetByIdAsync(int id)
        {
            var cacheKey = GetBranchByIdCacheKey(id);
            var cachedBranch = await _cache.GetStringAsync(cacheKey);
            if (!string.IsNullOrWhiteSpace(cachedBranch))
            {
                return JsonSerializer.Deserialize<BranchDTO>(cachedBranch);
            }

            var branch = await _repository.GetByIdAsync(id);
            if (branch == null)
            {
                return null;
            }

            var branchDto = MapToDTO(branch);
            await _cache.SetStringAsync(cacheKey, JsonSerializer.Serialize(branchDto), CacheOptions);

            return branchDto;
        }

        public async Task<BranchDTO> AddAsync(BranchCreateDTO dto)
        {
            var branch = new Branch
            {
                Name = dto.Name,
                Address = dto.Address,
                Phone = dto.Phone
            };
            var result = await _repository.AddAsync(branch);
            await InvalidateBranchCacheAsync(result.Id);
            return MapToDTO(result);
        }

        public async Task<BranchDTO> UpdateAsync(BranchDTO dto)
        {
            var branch = new Branch
            {
                Id = dto.Id,
                Name = dto.Name,
                Address = dto.Address,
                Phone = dto.Phone
            };
            var result = await _repository.UpdateAsync(branch);
            await InvalidateBranchCacheAsync(result.Id);
            return MapToDTO(result);
        }

        public async Task<BranchDTO> DeleteAsync(int id)
        {
            var result = await _repository.DeleteAsync(id);
            await InvalidateBranchCacheAsync(id);
            return result == null ? null : MapToDTO(result);
        }

        private async Task InvalidateBranchCacheAsync(int id)
        {
            await _cache.RemoveAsync(BranchListCacheKey);
            await _cache.RemoveAsync(GetBranchByIdCacheKey(id));
        }

        private static string GetBranchByIdCacheKey(int id) => $"branch:{id}";

        private BranchDTO MapToDTO(Branch branch)
        {
            return new BranchDTO
            {
                Id = branch.Id,
                Name = branch.Name,
                Address = branch.Address,
                Phone = branch.Phone
            };
        }
    }
}
