using Hospital_API.Interfaces;
using Hospital_API.Models;
using Hospital_API.DTOs;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
namespace Hospital_API.Services
{
    public class MedicalServiceService : IMedServiceService
    {
        private readonly IMedServiceRepo _medServiceRepo;
        public MedicalServiceService(IMedServiceRepo medServiceRepo)
        {
            _medServiceRepo = medServiceRepo;
        }
        // Get all medical services
        public async Task<IEnumerable<MedicalServiceDTO>> GetAllMedServices()
        {
            var medServices = await _medServiceRepo.GetAllMedServices();
            return medServices.Select(m => MapToDTO(m)).ToList();
        }
        // Get medical service by ID
        public async Task<MedicalServiceDTO> GetMedServiceById(int id)
        {
            var medService = await _medServiceRepo.GetMedServiceById(id);
            if (medService == null)
            {
                return null;
            }
            return MapToDTO(medService);
        }
        // Create a new medical service
        public async Task<MedicalServiceDTO> CreateMedService(MedicalServiceDTO medService)
        {
            var medServiceDb = new MedicalServiceDb
            {
                Name = medService.Name,
                Price = medService.Price,

                Type = medService.Type,
                Description = medService.Description
            };
            var createdMedService = await _medServiceRepo.CreateMedService(medServiceDb);
            return MapToDTO(createdMedService);
        }
        // Update an existing medical service
        public async Task<MedicalServiceDTO> UpdateMedService(MedicalServiceDTO medService)
        {
            var medServiceDb = new MedicalServiceDb
            {
                Id = medService.Id,
                Name = medService.Name,

                Type = medService.Type,
                Price = medService.Price,
                Description = medService.Description
            };
            var updatedMedService = await _medServiceRepo.UpdateMedService(medServiceDb);
            if (updatedMedService == null)
            {
                return null;
            }
            return MapToDTO(updatedMedService);
        }
        // Delete a medical service
        public async Task<MedicalServiceDTO> DeleteMedService(int id)
        {
            var medService = await _medServiceRepo.DeleteMedService(id);
            if (medService == null)
            {
                return null;
            }
            return MapToDTO(medService);
        }

        // Map to DTO
        public MedicalServiceDTO MapToDTO(MedicalServiceDb medService)
        {
            return new MedicalServiceDTO
            {
                Id = medService.Id,
                Name = medService.Name,

                Type = medService.Type,
                Price = medService.Price,
                Description = medService.Description
            };
        }
    }
}
