//******************************************
// operators.f90
// based on min-app code written by Oliver Fuhrer, MeteoSwiss
// modified by Ben Cumming, CSCS
// *****************************************

// Description: Contains simple operators which can be used on 3d-meshes

#include "check.h"
#include "data.h"
#include "operators.h"
#include "stats.h"

#define U(j,i)    up[(i) + (j)*nx]
#define S(j,i)    sp[(i) + (j)*nx]
#define X(j,i) x_old[(i) + (j)*nx]

namespace gpu
{
	__global__ void diffusion(const double* up, double* sp)
	{
		using namespace gpu;

		double dxs   = 1000.*options.dx*options.dx;
		double alpha = options.alpha;
		int    iend  = options.nx - 1;
		int    jend  = options.ny - 1;

		int i,j;

		int nx=options.nx;

		// the interior grid points
		for (j = 1; j < jend; j++)
		    for (i = 1; i < iend; i++)
		    {
		        S(j, i) = -(4. + alpha)*U(j,i)               // central point
		                                + U(j,i-1) + U(j,i+1) // east and west
		                                + U(j-1,i) + U(j+1,i) // north and south

		                                + alpha*X(j,i)
		                                + dxs*U(j,i)*(1.0 - U(j,i));
		    }
		// the east boundary
		{
		    i = options.nx - 1;
		    for (j = 1; j < jend; j++)
		    {
		        S(j, i) = -(4. + alpha) * U(j,i)
		                    + U(j, i - 1) + U(j - 1, i) + U(j + 1, i)
		                    + alpha*X(j, i) + bndE[j]
		                    + dxs * U(j, i) * (1.0 - U(j, i));
		    }
		}
		// the west boundary
		{
		    i = 0;
		    for (j = 1; j < jend; j++)
		    {
		        S(j, i) = -(4. + alpha) * U(j, i)
		                    + U(j, i + 1) + U(j - 1, i) + U(j + 1, i)

		                    + alpha*X(j, i) + bndW[j]
		                    + dxs*U(j, i) * (1.0 - U(j, i));
		    }
		}
		// the north boundary (plus NE and NW corners)
		{
		    j = options.ny - 1;

		    {
		        i = 0; // NW corner
		        S(j, i) = -(4. + alpha) * U(j, i)
		                    + U(j, i + 1) + U(j - 1, i)

		                    + alpha * X(j, i) + bndW[j] + bndN[i]
		                    + dxs * U(j, i) * (1.0 - U(j, i));
		    }

		    // north boundary
		    for (i = 1; i < iend; i++)
		    {
		        S(j, i) = -(4. + alpha) * U(j, i)
		                    + U(j, i - 1) + U(j, i + 1) + U(j - 1, i)
		                    + alpha*X(j, i) + bndN[i]
		                    + dxs * U(j, i) * (1.0 - U(j, i));
		    }

		    {
		        i = options.nx; // NE corner
		        S(j, i) = -(4. + alpha) * U(j, i)
		                    + U(j, i - 1) + U(j - 1, i)
		                    + alpha * X(j, i) + bndE[j] + bndN[i]
		                    + dxs * U(j, i) * (1.0 - U(j, i));
		    }
		}
		// the south boundary
		{
		    j = 0;
		    {
		        i = 0; // SW corner
		        S(j, i) = -(4. + alpha) * U(j, i)
		                    + U(j, i + 1) + U(j + 1, i)
		                    + alpha * X(j, i) + bndW[j] + bndS[i]
		                    + dxs * U(j, i) * (1.0 - U(j, i));
		    }
		    // south boundary
		    for (i = 1; i < iend; i++)
		    {
		        S(j, i) = -(4. + alpha) * U(j, i)
		                    + U(j, i - 1) + U(j, i + 1) + U(j + 1, i)
		                    + alpha * X(j, i) + bndS[i]
		                    + dxs * U(j, i) * (1.0 - U(j, i));
		    }
		    //
		    {
		        i = options.nx - 1; // SE corner
		        S(j, i) = -(4. + alpha) * U(j, i)
		                    + U(j, i - 1) + U(j + 1, i)
		                    + alpha * X(j, i) + bndE[j] + bndS[i]
		                    + dxs * U(j, i) * (1.0 - U(j, i));
		    }
		}
	}
}

void diffusion(const double* up, double* sp)
{
	using namespace cpu;

	int nx = options.nx;
	int ny = options.ny;

	// Allocate temporary GPU copies for "up" and "sp".
	double *up_gpu = NULL, *sp_gpu = NULL;
	CUDA_ERR_CHECK(cudaMalloc(&up_gpu, sizeof(double) * nx * ny));
	CUDA_ERR_CHECK(cudaMalloc(&sp_gpu, sizeof(double) * nx * ny));

	// Copy actual "up" data to GPU.
	CUDA_ERR_CHECK(cudaMemcpy(up_gpu, up, sizeof(double) * nx * ny, cudaMemcpyHostToDevice));

	// Copy actual x_old data to GPU.
	double** gpu_x_old;
	CUDA_ERR_CHECK(cudaGetSymbolAddress((void**)&gpu_x_old, gpu::x_old));
	double* gpu_x_old_value;
	CUDA_ERR_CHECK(cudaMemcpy(&gpu_x_old_value, gpu_x_old, sizeof(double*), cudaMemcpyDeviceToHost));
	CUDA_ERR_CHECK(cudaMemcpy(gpu_x_old_value, cpu::x_old, sizeof(double) * nx * ny, cudaMemcpyHostToDevice));
	
	// Launch kernel in single-threaded mode.
	gpu::diffusion<<<1, 1>>>(up_gpu, sp_gpu);
	
	// Copy back the resulting "sp" data.
	CUDA_ERR_CHECK(cudaMemcpy(sp, sp_gpu, sizeof(double) * nx * ny, cudaMemcpyDeviceToHost));
	
	// Free temporary GPU arrays.
	CUDA_ERR_CHECK(cudaFree(up_gpu));
	CUDA_ERR_CHECK(cudaFree(sp_gpu));

	// Accumulate the flop counts
	// 8 ops total per point
	flops_diff +=
	    + 12 * (options.nx - 2) * (options.ny - 2) // interior points
	    + 11 * (options.nx - 2  +  options.ny - 2) // NESW boundary points
	    + 11 * 4;                                  // corner points}
}

