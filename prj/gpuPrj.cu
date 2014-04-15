/*
 *   Description: use GPU to calculate parallel beam, fan beam projection 
 *   and their corresponding back projection.
 *
 *   Reference:
 *   Author: Renliang Gu (renliang@iastate.edu)
 *   $Revision: 0.1 $ $Date: Sun 10 Nov 2013 01:23:32 AM CST
 *
 *   v_0.1:     first draft
 */
#define GPU 1

/*#include <unistd.h>*/
#include <stdlib.h>
#include <math.h>
#include <stdio.h>
#include <time.h>
#include <pthread.h>
#include <limits.h>
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include "./common/kiss_fft.h"

#ifdef __cplusplus
extern "C"{
#endif
#include "prj.h"
#ifdef __cplusplus
}
#endif

#if EXE_PROF
#if GPU
#include <cuda_profiler_api.h>
#endif
#endif

#if SHOWIMG
#include "./common/cpu_bitmap.h"
#endif

struct prjConf config;
struct prjConf* pConf = &config;

#if GPU
cudaEvent_t     start, stop;

ft *dev_img;
ft *dev_sino;

static dim3 fGrid, fThread, bGrid, bThread;

__constant__ prjConf dConf;
#endif

#if GPU
/*
   */
static void HandleError( cudaError_t err,
                         const char *file,
                         int line ) {
    if (err != cudaSuccess) {
        printf( "%s in %s at line %d\n", cudaGetErrorString( err ),
                file, line );
        exit( EXIT_FAILURE );
    }
}
#endif

__global__ void pixelDrivePar(ft* img, ft* sino,int FBP){
    //printf("entering pixelDrive\n");
    // detector array is of odd size with the center at the middle
    ft theta;       // the current angle, range in [0 45]
    int thetaIdx; // index counts from 0
    prjConf* conf = &dConf;

    int pC = conf->prjWidth/2;
    int N=conf->n;

    int tileSz = sqrtf(blockDim.x);
    int tileX=0, tileY=blockIdx.x;
    while(tileY>tileX){ tileX++; tileY-=tileX; }

    int xl=tileX*tileSz, yt=tileY*tileSz;

    int x=xl+threadIdx.x/tileSz,
        y=yt+threadIdx.x%tileSz;

    ft cosT, sinT;  // cosine and sine of theta
    ft tileSzSinT, tileSzCosT;

    // for each point (x,y) on the ray is
    // x= t*cosT + (t*cosT+d*sinT)/(t*sinT-d*cosT)*(y-t*sinT);
    // or x = -t*d/(t*sinT-d*cosT) + y*(t*cosT+d*sinT)/(t*sinT-d*cosT);
    ft oc;
    ft beamWidth = conf->dSize*conf->effectiveRate;

    ft dist, weight;
    int temp, imgIdx;
    ft imgt[8];
    ft t, tl, tr, tll, trr;
    int dt, dtl, dtr, dtll, dtrr;
    for(int i=0; i<8; i++) imgt[i]=0;
    __shared__ volatile ft shared[8][ANG_BLK][4*TILE_SZ];
    for(thetaIdx=0; thetaIdx<conf->prjFull/2;thetaIdx++){

        theta  = thetaIdx *2*PI/conf->prjFull;
        cosT = cos(theta ); sinT = sin(theta );
        tileSzCosT=tileSz*cosT; tileSzSinT=tileSz*sinT;

        // up letf
        oc = (xl-0.5)*cosT + (yt-0.5)*sinT; tll = oc; trr = tll;

        // up right
        //qe = (xr+0.5)*sinTl - (yt-0.5)*cosTl + d;
        //oc = (xr+0.5)*cosTl + (yt-0.5)*sinTl;
        oc = oc+tileSzCosT; t=oc; tll = min(tll, t); trr=max(trr,t);

        // bottom right
        //qe = (xr+0.5)*sinTl - (yb+0.5)*cosTl + d;
        //oc = (xr+0.5)*cosTl + (yb+0.5)*sinTl;
        oc = oc+tileSzSinT; t=oc; tll = min(tll, t); trr=max(trr,t);

        // bottom left
        //qe = (xl-0.5)*sinTl - (yb+0.5)*cosTl + d;
        //oc = (xl-0.5)*cosTl + (yb+0.5)*sinTl;
        oc = oc-tileSzCosT; t=oc; tll = min(tll, t); trr=max(trr,t);

        // up letf
        oc = (x-0.5)*cosT + (y-0.5)*sinT;
        tl = oc; tr = tl;

        // up right
        //qe = (x+0.5)*sinT - (y-0.5)*cosT + d;
        //oc = (x+0.5)*cosT + (y-0.5)*sinT;
        oc = oc + cosT; t = oc;
        tl = min(tl, t); tr=max(tr,t);

        // bottom right
        //qe = (x+0.5)*sinT - (y+0.5)*cosT + d;
        //oc = (x+0.5)*cosT + (y+0.5)*sinT;
        oc=oc+sinT; t = oc;
        tl = min(tl, t); tr=max(tr,t);

        // bottom left
        //qe = (x-0.5)*sinT - (y+0.5)*cosT + d;
        //oc = (x-0.5)*cosT + (y+0.5)*sinT;
        oc = oc-cosT; t = oc;
        tl = min(tl, t); tr=max(tr,t);

        //qe = d+x*sinT-y*cosT; // positive direction is qo
        dtl = max((int)round((tl)/conf->dSize),-(conf->prjWidth-1)/2);
        dtr = min((int)round((tr)/conf->dSize), (conf->prjWidth-1)/2);

        dtll=max((int)round((tll)/conf->dSize),-(conf->prjWidth-1)/2);
        dtrr=min((int)round((trr)/conf->dSize), (conf->prjWidth-1)/2);

        dtl = max(dtl,dtll); dtr=min(dtr,dtrr);

        __syncthreads();
        for(dt=dtll+threadIdx.x; dt<=dtrr; dt+=blockDim.x){
            temp=thetaIdx;
            shared[0][0][dt-dtll]=temp<conf->np? sino[temp*conf->prjWidth+dt+pC] : 0;
            shared[0][1][dt-dtll]=temp<conf->np? sino[temp*conf->prjWidth-dt+pC] : 0;

            temp=(thetaIdx+conf->prjFull/4)%conf->prjFull;
            shared[1][0][dt-dtll]=temp<conf->np? sino[temp*conf->prjWidth+dt+pC] : 0;
            shared[1][1][dt-dtll]=temp<conf->np? sino[temp*conf->prjWidth-dt+pC] : 0;

            temp=(thetaIdx+conf->prjFull/2)%conf->prjFull;
            shared[2][0][dt-dtll]=temp<conf->np? sino[temp*conf->prjWidth+dt+pC] : 0;
            shared[2][1][dt-dtll]=temp<conf->np? sino[temp*conf->prjWidth-dt+pC] : 0;

            temp=(thetaIdx+3*conf->prjFull/4)%conf->prjFull;
            shared[3][0][dt-dtll]=temp<conf->np? sino[temp*conf->prjWidth+dt+pC] : 0;
            shared[3][1][dt-dtll]=temp<conf->np? sino[temp*conf->prjWidth-dt+pC] : 0;

            temp=(3*conf->prjFull/2-thetaIdx)%conf->prjFull;
            shared[4][0][dt-dtll]=temp<conf->np? sino[temp*conf->prjWidth-dt+pC] : 0;
            shared[4][1][dt-dtll]=temp<conf->np? sino[temp*conf->prjWidth+dt+pC] : 0;

            temp=(7*conf->prjFull/4-thetaIdx)%conf->prjFull;
            shared[5][0][dt-dtll]=temp<conf->np? sino[temp*conf->prjWidth-dt+pC] : 0;
            shared[5][1][dt-dtll]=temp<conf->np? sino[temp*conf->prjWidth+dt+pC] : 0;

            temp=(conf->prjFull-thetaIdx)%conf->prjFull;
            shared[6][0][dt-dtll]=temp<conf->np? sino[temp*conf->prjWidth-dt+pC] : 0;
            shared[6][1][dt-dtll]=temp<conf->np? sino[temp*conf->prjWidth+dt+pC] : 0;

            temp=(5*conf->prjFull/4-thetaIdx)%conf->prjFull;
            shared[7][0][dt-dtll]=temp<conf->np? sino[temp*conf->prjWidth-dt+pC] : 0;
            shared[7][1][dt-dtll]=temp<conf->np? sino[temp*conf->prjWidth+dt+pC] : 0;
        }
        __syncthreads();

        for(dt=dtl; dt<=dtr; dt++){
            t = dt*conf->dSize;
            dist=x*cosT+y*sinT-t;
            weight=getWeight(dist,beamWidth,cosT,sinT);

            imgt[0] += weight*shared[0][0][dt-dtll];
            imgt[2] += weight*shared[0][1][dt-dtll];
            imgt[1] += weight*shared[1][0][dt-dtll];
            imgt[3] += weight*shared[1][1][dt-dtll];
            imgt[2] += weight*shared[2][0][dt-dtll];
            imgt[0] += weight*shared[2][1][dt-dtll];
            imgt[3] += weight*shared[3][0][dt-dtll];
            imgt[1] += weight*shared[3][1][dt-dtll];
            imgt[4] += weight*shared[4][0][dt-dtll];
            imgt[6] += weight*shared[4][1][dt-dtll];
            imgt[5] += weight*shared[5][0][dt-dtll];
            imgt[7] += weight*shared[5][1][dt-dtll];
            imgt[6] += weight*shared[6][0][dt-dtll];
            imgt[4] += weight*shared[6][1][dt-dtll];
            imgt[7] += weight*shared[7][0][dt-dtll];
            imgt[5] += weight*shared[7][1][dt-dtll];
        }
    }
    if(FBP) for(int i=0; i<8; i++) imgt[i]=imgt[i]*PI/conf->np;
    if(x>(N-1)/2 || y>(N-1)/2) return;
    imgIdx = ( y+N/2)*N+x+N/2; img[imgIdx] = imgt[0]/conf->effectiveRate;
    imgIdx = ( x+N/2)*N-y+N/2; img[imgIdx] = imgt[1]/conf->effectiveRate;
    imgIdx = (-y+N/2)*N-x+N/2; img[imgIdx] = imgt[2]/conf->effectiveRate;
    imgIdx = (-x+N/2)*N+y+N/2; img[imgIdx] = imgt[3]/conf->effectiveRate;
    if(y==0 || y>=x) return;
    imgIdx = (-y+N/2)*N+x+N/2; img[imgIdx] = imgt[4]/conf->effectiveRate;
    imgIdx = ( x+N/2)*N+y+N/2; img[imgIdx] = imgt[5]/conf->effectiveRate;
    imgIdx = ( y+N/2)*N-x+N/2; img[imgIdx] = imgt[6]/conf->effectiveRate;
    imgIdx = (-x+N/2)*N-y+N/2; img[imgIdx] = imgt[7]/conf->effectiveRate;
}

__global__ void pixelDriveFan(ft* img, ft* sino, int FBP){
    //printf("entering pixelDrive\n");
    // detector array is of odd size with the center at the middle
    ft theta;       // the current angle, range in [0 45]
    int thetaIdx; // index counts from 0
    prjConf* conf = &dConf;

    int pC = conf->prjWidth/2;
    ft d=conf->d; // the distance from rotating center to source in pixel
    int N=conf->n;

    int tileSz = sqrtf(blockDim.x);
    int tileX=0, tileY=blockIdx.x;
    while(tileY>tileX){ tileX++; tileY-=tileX; }

    int xl=tileX*tileSz, yt=tileY*tileSz;

    int x=xl+threadIdx.x/tileSz,
        y=yt+threadIdx.x%tileSz;

    ft cosT, sinT;  // cosine and sine of theta
    ft tileSzSinT, tileSzCosT;

    // for each point (x,y) on the ray is
    // x= t*cosT + (t*cosT+d*sinT)/(t*sinT-d*cosT)*(y-t*sinT);
    // or x = -t*d/(t*sinT-d*cosT) + y*(t*cosT+d*sinT)/(t*sinT-d*cosT);
    ft qe, oc, qa;
    ft bq;
    ft cosB, sinB; //, tanB=t/d;
    ft cosR, sinR;
    ft beamWidth = conf->dSize*conf->effectiveRate;
    ft bw;

    ft dist, weight;
    int temp, imgIdx;
    ft imgt[8];
    ft t, tl, tr, tll, trr;
    int dt, dtl, dtr, dtll, dtrr;
    for(int i=0; i<8; i++) imgt[i]=0;
    __shared__ volatile ft shared[8][ANG_BLK][4*TILE_SZ];
    for(thetaIdx=0; thetaIdx<conf->prjFull;thetaIdx++){

        theta  = thetaIdx *2*PI/conf->prjFull;
        cosT = cos(theta ); sinT = sin(theta );
        tileSzCosT=tileSz*cosT; tileSzSinT=tileSz*sinT;

        // up letf
        qe = (xl-0.5)*sinT - (yt-0.5)*cosT + d;
        oc = (xl-0.5)*cosT + (yt-0.5)*sinT;
        tll = d*oc/qe; trr = tll;

        // up right
        //qe = (xr+0.5)*sinTl - (yt-0.5)*cosTl + d;
        //oc = (xr+0.5)*cosTl + (yt-0.5)*sinTl;
        qe = qe+tileSzSinT; oc = oc+tileSzCosT; t=d*oc/qe;
        tll = min(tll, t); trr=max(trr,t);

        // bottom right
        //qe = (xr+0.5)*sinTl - (yb+0.5)*cosTl + d;
        //oc = (xr+0.5)*cosTl + (yb+0.5)*sinTl;
        qe = qe-tileSzCosT; oc = oc+tileSzSinT; t=d*oc/qe;
        tll = min(tll, t); trr=max(trr,t);

        // bottom left
        //qe = (xl-0.5)*sinTl - (yb+0.5)*cosTl + d;
        //oc = (xl-0.5)*cosTl + (yb+0.5)*sinTl;
        qe = qe-tileSzSinT; oc = oc-tileSzCosT; t=d*oc/qe;
        tll = min(tll, t); trr=max(trr,t);

        // up letf
        qe = (x-0.5)*sinT - (y-0.5)*cosT + d;
        oc = (x-0.5)*cosT + (y-0.5)*sinT;
        tl = d*oc/qe; tr = tl;

        // up right
        //qe = (x+0.5)*sinT - (y-0.5)*cosT + d;
        //oc = (x+0.5)*cosT + (y-0.5)*sinT;
        qe = qe+sinT; oc = oc + cosT; t = d*oc/qe;
        tl = min(tl, t); tr=max(tr,t);

        // bottom right
        //qe = (x+0.5)*sinT - (y+0.5)*cosT + d;
        //oc = (x+0.5)*cosT + (y+0.5)*sinT;
        qe = qe-cosT; oc=oc+sinT; t = d*oc/qe;
        tl = min(tl, t); tr=max(tr,t);

        // bottom left
        //qe = (x-0.5)*sinT - (y+0.5)*cosT + d;
        //oc = (x-0.5)*cosT + (y+0.5)*sinT;
        qe = qe-sinT; oc = oc-cosT; t = d*oc/qe;
        tl = min(tl, t); tr=max(tr,t);

        dtll=max((int)round((tll)/conf->dSize),-(conf->prjWidth-1)/2);
        dtrr=min((int)round((trr)/conf->dSize), (conf->prjWidth-1)/2);

        dtl = max((int)round((tl)/conf->dSize),-(conf->prjWidth-1)/2);
        dtr = min((int)round((tr)/conf->dSize), (conf->prjWidth-1)/2);
        dtl = max(dtl,dtll); dtr=min(dtr,dtrr);

        //qe = d+x*sinT-y*cosT; // positive direction is qo
        qe = qe + sinT/2 +cosT/2;
        qa = sqrt(2*d*qe-d*d+x*x+y*y);

        __syncthreads();
        for(dt=dtll+threadIdx.x; dt<=dtrr; dt+=blockDim.x){
            temp=thetaIdx;
            shared[0][0][dt-dtll]=thetaIdx<conf->n ? sino[temp*conf->prjWidth+dt+pC] : 0;

            temp=(thetaIdx+conf->prjFull/4)%conf->prjFull;
            shared[1][0][dt-dtll]=thetaIdx<conf->n ? sino[temp*conf->prjWidth+dt+pC] : 0;

            temp=(thetaIdx+conf->prjFull/2)%conf->prjFull;
            shared[2][0][dt-dtll]=thetaIdx<conf->n ? sino[temp*conf->prjWidth+dt+pC] : 0;

            temp=(thetaIdx+3*conf->prjFull/4)%conf->prjFull;
            shared[3][0][dt-dtll]=thetaIdx<conf->n ? sino[temp*conf->prjWidth+dt+pC] : 0;

            temp=(3*conf->prjFull/2-thetaIdx)%conf->prjFull;
            shared[4][0][dt-dtll]=thetaIdx<conf->n ? sino[temp*conf->prjWidth-dt+pC] : 0;

            temp=(7*conf->prjFull/4-thetaIdx)%conf->prjFull;
            shared[5][0][dt-dtll]=thetaIdx<conf->n ? sino[temp*conf->prjWidth-dt+pC] : 0;

            temp=(conf->prjFull-thetaIdx)%conf->prjFull;
            shared[6][0][dt-dtll]=thetaIdx<conf->n ? sino[temp*conf->prjWidth-dt+pC] : 0;

            temp=(5*conf->prjFull/4-thetaIdx)%conf->prjFull;
            shared[7][0][dt-dtll]=thetaIdx<conf->n ? sino[temp*conf->prjWidth-dt+pC] : 0;
        }
        __syncthreads();

        for(dt=dtl; dt<=dtr; dt++){
            t = dt*conf->dSize;
            bq=sqrt(d*d+t*t);
            cosB=d/bq; sinB=t/bq; //, tanB=t/d;
            cosR=cosB*cosT-sinB*sinT;
            sinR=sinB*cosT+cosB*sinT;
            dist=x*cosR+y*sinR-d*t/bq;
            bw = qe*beamWidth*cosB/d;
            weight=getWeight(dist,bw,cosR,sinR);

            // method provide by the books
            //if(FBP) weight = weight*d*d/qe/qe;
            // The one I think should be
            if(FBP) weight = weight*d/qa;
            //if(FBP) weight = weight*d/qe;

            imgt[0] += weight*shared[0][0][dt-dtll];
            imgt[1] += weight*shared[1][0][dt-dtll];
            imgt[2] += weight*shared[2][0][dt-dtll];
            imgt[3] += weight*shared[3][0][dt-dtll];
            imgt[4] += weight*shared[4][0][dt-dtll];
            imgt[5] += weight*shared[5][0][dt-dtll];
            imgt[6] += weight*shared[6][0][dt-dtll];
            imgt[7] += weight*shared[7][0][dt-dtll];

        }
    }
    if(FBP) for(int i=0; i<8; i++) imgt[i]=imgt[i]*PI/conf->np;
    if(x>(N-1)/2 || y>(N-1)/2) return;
    imgIdx = ( y+N/2)*N+x+N/2; img[imgIdx] = imgt[0]/conf->effectiveRate;
    imgIdx = ( x+N/2)*N-y+N/2; img[imgIdx] = imgt[1]/conf->effectiveRate;
    imgIdx = (-y+N/2)*N-x+N/2; img[imgIdx] = imgt[2]/conf->effectiveRate;
    imgIdx = (-x+N/2)*N+y+N/2; img[imgIdx] = imgt[3]/conf->effectiveRate;
    if(y==0 || y>=x) return;
    imgIdx = (-y+N/2)*N+x+N/2; img[imgIdx] = imgt[4]/conf->effectiveRate;
    imgIdx = ( x+N/2)*N+y+N/2; img[imgIdx] = imgt[5]/conf->effectiveRate;
    imgIdx = ( y+N/2)*N-x+N/2; img[imgIdx] = imgt[6]/conf->effectiveRate;
    imgIdx = (-x+N/2)*N-y+N/2; img[imgIdx] = imgt[7]/conf->effectiveRate;
}

__global__ void rayDrivePar(ft* img, ft* sino){
    //printf("entering rayDrive\n");
    // detector array is of odd size with the center at the middle
    prjConf* conf = &dConf;
    int sinoIdx;
    int thetaIdx = blockIdx.x;
    int tIdx = blockIdx.y*blockDim.x+threadIdx.x;
    int tllIdx = blockIdx.y*blockDim.x;
    int trrIdx = blockIdx.y*blockDim.x+blockDim.x-1;

    if(conf->prjWidth%2==0){
        tIdx++; tllIdx++; trrIdx++;
    }
    //printf("tIdx=%d, thetaIdx=%d\n",tIdx, thetaIdx);

    //if(blockIdx.x==0 && blockIdx.y==0)
    //    printf("gridDim=(%d, %d)\t blockDim=(%d, %d)\n",
    //            gridDim.x, gridDim.y, blockDim.x, blockDim.y);

    ft theta;       // the current angle, range in [0 45]
    ft t;           // position of current detector

    int N =conf->n;// N is of size NxN centering at (N/2,N/2)
    int pC = conf->prjWidth/2;
    ft beamWidth = conf->dSize*conf->effectiveRate;
    ft hbeamW = beamWidth/2;

    __shared__ volatile ft shared[8][2*THRD_SZ];
    // the length should be at least blockDim.x*sqrt(2)*(1+N/2/d)

    theta = thetaIdx*2*PI/conf->prjFull;
    t = (tIdx-pC)*conf->dSize;
    ft tl = t-hbeamW,
       tr = t+hbeamW,
       tll = (tllIdx-pC)*conf->dSize-hbeamW,
       trr = (trrIdx-pC)*conf->dSize+hbeamW;

    ft cosT, sinT;  // cosine and sine of theta
    cosT=cos(theta); sinT=sin(theta);

    // for each point (x,y) on the ray is
    // x= t*cosT + (t*cosT+d*sinT)/(t*sinT-d*cosT)*(y-t*sinT);
    // or x = -t*d/(t*sinT-d*cosT) + y*(t*cosT+d*sinT)/(t*sinT-d*cosT);

    //if(tIdx==pC && thetaIdx==30){
    //    printf("theta=%f,cosT=%f, sinT=%f\n",theta,cosT,sinT);
    //    printf("cosB=%f, sinB=%f\n",cosB,sinB);
    //}

    ft   xl, xll, xr, xrr;
    int dxl,dxll,dxr,dxrr;

    int x,y=(N-1)/2;
    //xc = xc + y*slopeXYc;

    // beamw is based on the position of this pixel
    ft dist, weight;
    int temp;
    ft sinot[8];
    for(int i=0; i<8; i++) sinot[i]=0;
    for(y=(N-1)/2; y>=-(N-1)/2; y--){
        xl = ( tl-sinT *(y+0.5f))/cosT;
        xr = ( tr-sinT *(y-0.5f))/cosT;
        xll= (tll-sinT *(y+0.5f))/cosT;
        xrr= (trr-sinT *(y-0.5f))/cosT;

        dxll=max((int)round(xll),-(N-1)/2);
        dxrr=min((int)round(xrr), (N-1)/2);
        dxl =max((int)round(xl ),-(N-1)/2);
        dxr =min((int)round(xr ), (N-1)/2);
        if(dxl<dxll || dxr>dxrr) printf("rayDrivePar:%d, %d; %d, %d\n",
                dxll,dxl,dxr,dxrr);
        dxl =max(dxl,dxll); dxr=min(dxr,dxrr);

        __syncthreads();
        for(x=dxll+threadIdx.x, temp=threadIdx.x; x<=dxrr;
                x+=blockDim.x, temp+=blockDim.x){
            shared[0][temp] = img[( y+N/2)*N+x+N/2];
            shared[1][temp] = img[( x+N/2)*N-y+N/2];
            shared[2][temp] = img[(-y+N/2)*N-x+N/2];
            shared[3][temp] = img[(-x+N/2)*N+y+N/2];
            shared[4][temp] = img[(-y+N/2)*N+x+N/2];
            shared[5][temp] = img[( x+N/2)*N+y+N/2];
            shared[6][temp] = img[( y+N/2)*N-x+N/2];
            shared[7][temp] = img[(-x+N/2)*N-y+N/2];
        }
        __syncthreads();
        //if(thetaIdx==45 && blockIdx.y==1 && threadIdx.x==0){
        //    printf("\nthetaIdx=%d, t=%f, y=%d, %d->%d\n \t",
        //            thetaIdx,t,y,dxll,dxrr);
        //    for(temp=0; temp<=dxrr-dxll; temp++){
        //        if(shared[1][temp]>0)
        //            printf("%d: %d: %f",temp,temp+dxll,shared[1][temp]);
        //    }
        //}
        for(x=dxl; x<=dxr; x++){
            dist=x*cosT+y*sinT-t;
            weight=getWeight(dist,beamWidth,cosT,sinT);

            sinot[0]+=weight*shared[0][x-dxll];

            //if(thetaIdx==42 && blockIdx.y==4 && threadIdx.x==0){
            //    printf("%d %d %e %e %e\n",y,x,weight, weight*shared[0][x-dxll],sinot[0]);
            //}

            //temp=thetaIdx+conf->prjFull/4;
            sinot[1]+=weight*shared[1][x-dxll]; //img[imgIdx];
            //temp+=conf->prjFull/4;
            sinot[2]+=weight*shared[2][x-dxll]; //img[imgIdx];
            //temp+=conf->prjFull/4;
            sinot[3]+=weight*shared[3][x-dxll]; //img[imgIdx];
            //temp=conf->prjFull/2-thetaIdx;
            sinot[4]+=weight*shared[4][x-dxll]; //img[imgIdx];
            //temp=3*conf->prjFull/4-thetaIdx;
            sinot[5]+=weight*shared[5][x-dxll]; //img[imgIdx];
            //temp=conf->prjFull-thetaIdx;
            sinot[6]+=weight*shared[6][x-dxll]; //img[imgIdx];
            //temp=conf->prjFull/4-thetaIdx;
            sinot[7]+=weight*shared[7][x-dxll]; //img[imgIdx];
        }
    }

    if(tIdx>pC) return;

    if(thetaIdx<conf->np){
        sinoIdx=thetaIdx*conf->prjWidth;
        sino[sinoIdx+tIdx]=sinot[0]/conf->effectiveRate;
        sino[sinoIdx+2*pC-tIdx]=sinot[2]/conf->effectiveRate;
    }

    temp = thetaIdx+conf->prjFull/4;
    if(temp<conf->np){
        sinoIdx = temp*conf->prjWidth;
        sino[sinoIdx+tIdx]=sinot[1]/conf->effectiveRate;
        sino[sinoIdx+2*pC-tIdx]=sinot[3]/conf->effectiveRate;
    }

    temp = thetaIdx+conf->prjFull/2;
    if(temp<conf->np){
        sinoIdx = temp*conf->prjWidth;
        sino[sinoIdx+tIdx]=sinot[2]/conf->effectiveRate;
        sino[sinoIdx+2*pC-tIdx]=sinot[0]/conf->effectiveRate;
    }

    temp = thetaIdx+3*conf->prjFull/4;
    if(temp<conf->np){
        sinoIdx = temp*conf->prjWidth;
        sino[sinoIdx+tIdx]=sinot[3]/conf->effectiveRate;
        sino[sinoIdx+2*pC-tIdx]=sinot[1]/conf->effectiveRate;
    }

    if(thetaIdx>0 && thetaIdx<conf->prjFull*0.125f){
        tIdx = 2*pC-tIdx;

        temp = conf->prjFull/2-thetaIdx;
        if(temp<conf->np){
            sinoIdx = temp*conf->prjWidth;
            sino[sinoIdx+tIdx]=sinot[4]/conf->effectiveRate;
            sino[sinoIdx+2*pC-tIdx]=sinot[6]/conf->effectiveRate;
        }

        temp = 3*conf->prjFull/4-thetaIdx;
        if(temp<conf->np){
            sinoIdx = temp*conf->prjWidth;
            sino[sinoIdx+tIdx]=sinot[5]/conf->effectiveRate;
            sino[sinoIdx+2*pC-tIdx]=sinot[7]/conf->effectiveRate;
        }

        temp = conf->prjFull-thetaIdx;
        if(temp<conf->np){
            sinoIdx = temp*conf->prjWidth;
            sino[sinoIdx+tIdx]=sinot[6]/conf->effectiveRate;
            sino[sinoIdx+2*pC-tIdx]=sinot[4]/conf->effectiveRate;
        }

        temp = conf->prjFull/4-thetaIdx;
        if(temp<conf->np){
            sinoIdx = temp*conf->prjWidth;
            sino[sinoIdx+tIdx]=sinot[7]/conf->effectiveRate;
            sino[sinoIdx+2*pC-tIdx]=sinot[5]/conf->effectiveRate;
        }
    }
}

__global__ void rayDriveFan(ft* img, ft* sino){
    // printf("entering rayDrive\n");
    // detector array is of odd size with the center at the middle
    prjConf* conf = &dConf;
    int sinoIdx;
    int thetaIdx = blockIdx.x;
    int tIdx   = blockIdx.y*blockDim.x+threadIdx.x;
    int tllIdx = blockIdx.y*blockDim.x;
    int trrIdx = blockIdx.y*blockDim.x+blockDim.x-1;

    if(conf->prjWidth%2==0){
        tIdx++; trrIdx++; tllIdx++;
    }
    //printf("tIdx=%d, thetaIdx=%d\n",tIdx, thetaIdx);

#if DEBUG
    if(blockIdx.x==0 && blockIdx.y==0 && threadIdx.x==0)
        printf("gridDim=(%d, %d)\t blockDim=(%d, %d)\n",
                gridDim.x, gridDim.y, blockDim.x, blockDim.y);
#endif

    ft theta;       // the current angle, range in [0 45]
    ft t;           // position of current detector
    ft d;           // the distance from rotating center to X-ray source in pixel

    int N =conf->n;// N is of size NxN centering at (N/2,N/2)
    int pC = conf->prjWidth/2;
    ft beamWidth = conf->dSize*conf->effectiveRate;
    ft hbeamW = beamWidth/2;

    // adding shared memory improves performance from 2.1s to 1.3s in 
    // Quadro 600
    // improves from 0.2s to 0.08s in Tesla K20
    // improves from 0.2s to 0.18s in Tesla K10

    __shared__ volatile ft shared[8][2*THRD_SZ];
    // the length should be at least blockDim.x*sqrt(2)*(1+N/2/d)

    theta = thetaIdx*2*PI/conf->prjFull;
    t = (tIdx-pC)*conf->dSize;
    ft tl = t-hbeamW,
       tr = t+hbeamW,
       tll = (tllIdx-pC)*conf->dSize-hbeamW,
       trr = (trrIdx-pC)*conf->dSize+hbeamW;
    d = conf->d;

    ft cosT, sinT;  // cosine and sine of theta
    cosT=cos(theta); sinT=sin(theta);

    // for each point (x,y) on the ray is
    // x= t*cosT + (t*cosT+d*sinT)/(t*sinT-d*cosT)*(y-t*sinT);
    // or x = -t*d/(t*sinT-d*cosT) + y*(t*cosT+d*sinT)/(t*sinT-d*cosT);
    ft bq=sqrt(d*d+t*t);
    ft cosB=d/bq, sinB=t/bq; //, tanB=t/d;
    ft cosR=cosB*cosT-sinB*sinT; // cosR and sinR are based on t
    ft sinR=sinB*cosT+cosB*sinT;
    ft beamwidthCosB=beamWidth*cosB;

    //if(tIdx==pC && thetaIdx==30){
    //    printf("theta=%f,cosT=%f, sinT=%f\n",theta,cosT,sinT);
    //    printf("cosB=%f, sinB=%f\n",cosB,sinB);
    //}

    ft dtl=d*tl, dtll=d*tll, dtr=d*tr, dtrr=d*trr;
    ft QxBxl = tl *cosT+d*sinT, QxBxr = tr *cosT+d*sinT,
       QxBxll= tll*cosT+d*sinT, QxBxrr= trr*cosT+d*sinT;

    ft QyByl =-tl *sinT+d*cosT, QyByr =-tr *sinT+d*cosT,
       QyByll=-tll*sinT+d*cosT, QyByrr=-trr*sinT+d*cosT;

    ft   xl, xll, xr, xrr;
    int dxl,dxll,dxr,dxrr;

    int x,y=(N-1)/2;
    //xc = xc + y*slopeXYc;

    // beamw is based on the position of this pixel
    ft bw, dist, weight;
    int temp;
    ft sinot[8];
    for(int i=0; i<8; i++) sinot[i]=0;
    for(y=(N-1)/2; y>=-(N-1)/2; y--){
        if(QxBxl>0) xl = (dtl - QxBxl *(y+0.5f))/QyByl;
        else xl = (dtl -QxBxl *(y-0.5f))/QyByl;
        if(QxBxr>0) xr = (dtr - QxBxr *(y-0.5f))/QyByr;
        else xr = (dtr - QxBxr *(y+0.5f))/QyByr;

        if(QxBxll>0) xll= (dtll- QxBxll*(y+0.5f))/QyByll;
        else xll= (dtll-QxBxll*(y-0.5f))/QyByll;
        if(QxBxrr>0) xrr= (dtrr- QxBxrr*(y-0.5f))/QyByrr;
        else xrr= (dtrr- QxBxrr*(y+0.5f))/QyByrr;

        dxll=max((int)round(xll),-(N-1)/2);
        dxrr=min((int)round(xrr), (N-1)/2);
        dxl =max((int)round(xl ),-(N-1)/2);
        dxr =min((int)round(xr ), (N-1)/2);
        dxl =max(dxl,dxll); dxr=min(dxr,dxrr);

        __syncthreads();
        for(x=dxll+threadIdx.x, temp=threadIdx.x; x<=dxrr;
                x+=blockDim.x, temp+=blockDim.x){
            shared[0][temp] = img[( y+N/2)*N+x+N/2];
            shared[1][temp] = img[( x+N/2)*N-y+N/2];
            shared[2][temp] = img[(-y+N/2)*N-x+N/2];
            shared[3][temp] = img[(-x+N/2)*N+y+N/2];
            shared[4][temp] = img[(-y+N/2)*N+x+N/2];
            shared[5][temp] = img[( x+N/2)*N+y+N/2];
            shared[6][temp] = img[( y+N/2)*N-x+N/2];
            shared[7][temp] = img[(-x+N/2)*N-y+N/2];
        }
        __syncthreads();
        //if(thetaIdx==45 && blockIdx.y==1 && threadIdx.x==0){
        //    printf("\nthetaIdx=%d, t=%f, y=%d, %d->%d\n \t",
        //            thetaIdx,t,y,dxll,dxrr);
        //    for(temp=0; temp<=dxrr-dxll; temp++){
        //        if(shared[1][temp]>0)
        //            printf("%d: %d: %f",temp,temp+dxll,shared[1][temp]);
        //    }
        //}
        for(x=dxl; x<=dxr; x++){

            dist=x*cosR+y*sinR-d*t/bq;
            bw=beamwidthCosB + (x*sinT-y*cosT)*beamwidthCosB/d;
            weight=getWeight(dist,bw,cosR,sinR);

            sinot[0]+=weight*shared[0][x-dxll];

            //if(thetaIdx==42 && blockIdx.y==4 && threadIdx.x==0){
            //    printf("%d %d %e %e %e\n",y,x,weight, weight*shared[0][x-dxll],sinot[0]);
            //}

            //temp=thetaIdx+conf->prjFull/4;
            sinot[1]+=weight*shared[1][x-dxll]; //img[imgIdx];
            //temp+=conf->prjFull/4;
            sinot[2]+=weight*shared[2][x-dxll]; //img[imgIdx];
            //temp+=conf->prjFull/4;
            sinot[3]+=weight*shared[3][x-dxll]; //img[imgIdx];
            //temp=conf->prjFull/2-thetaIdx;
            sinot[4]+=weight*shared[4][x-dxll]; //img[imgIdx];
            //temp=3*conf->prjFull/4-thetaIdx;
            sinot[5]+=weight*shared[5][x-dxll]; //img[imgIdx];
            //temp=conf->prjFull-thetaIdx;
            sinot[6]+=weight*shared[6][x-dxll]; //img[imgIdx];
            //temp=conf->prjFull/4-thetaIdx;
            sinot[7]+=weight*shared[7][x-dxll]; //img[imgIdx];
        }
    }

    if(tIdx>=conf->prjWidth) return;

    if(thetaIdx<conf->np){
        sinoIdx=thetaIdx*conf->prjWidth+tIdx;
        sino[sinoIdx]=sinot[0]/conf->effectiveRate;
    }

    temp = thetaIdx+conf->prjFull/4;
    if(temp<conf->np){
        sino[temp*conf->prjWidth+tIdx]=sinot[1]/conf->effectiveRate;
    }

    temp = thetaIdx+conf->prjFull/2;
    if(temp<conf->np){
        sino[temp*conf->prjWidth+tIdx]=sinot[2]/conf->effectiveRate;
    }

    temp = thetaIdx+3*conf->prjFull/4;
    if(temp<conf->np){
        sino[temp*conf->prjWidth+tIdx]=sinot[3]/conf->effectiveRate;
    }

    if(thetaIdx>0 && thetaIdx<conf->prjFull*0.125f){
        tIdx = 2*pC-tIdx;

        temp = conf->prjFull/2-thetaIdx;
        if(temp<conf->np)
            sino[temp*conf->prjWidth+tIdx]=sinot[4]/conf->effectiveRate;

        temp = 3*conf->prjFull/4-thetaIdx;
        if(temp<conf->np)
            sino[temp*conf->prjWidth+tIdx]=sinot[5]/conf->effectiveRate;

        temp = conf->prjFull-thetaIdx;
        if(temp<conf->np)
            sino[temp*conf->prjWidth+tIdx]=sinot[6]/conf->effectiveRate;

        temp = conf->prjFull/4-thetaIdx;
        if(temp<conf->np)
            sino[temp*conf->prjWidth+tIdx]=sinot[7]/conf->effectiveRate;
    }
}

#ifdef __cplusplus
extern "C"
#endif
void setup(int n, int prjWidth, int np, int prjFull, ft dSize, ft 
        effectiveRate, ft d){
    config.n=n; config.prjWidth=prjWidth;
    config.np=np; config.prjFull=prjFull;
    config.dSize=dSize; config.effectiveRate=effectiveRate;
    config.d=d;

    config.imgSize=config.n*config.n;
    config.sinoSize=config.prjWidth*config.np;

    if(config.d>0){
        if(pConf->prjWidth%2==0)
            fGrid = dim3(
                min(pConf->np, pConf->prjFull/8+1),
                (pConf->prjWidth-1+THRD_SZ-1)/THRD_SZ
                );
        else
            fGrid = dim3(
                min(pConf->np, pConf->prjFull/8+1),
                (pConf->prjWidth+THRD_SZ-1)/THRD_SZ
                );
        fThread = dim3(THRD_SZ,LYR_BLK);

        // use the last block to make frame zero.
        int temp = ((pConf->n+1)/2+TILE_SZ-1)/TILE_SZ;
        bGrid = dim3((1+temp)*temp/2);
        bThread = dim3(TILE_SZ*TILE_SZ, ANG_BLK);
    }else{
        fGrid = dim3(
                min(pConf->np, pConf->prjFull/8+1),
                ((pConf->prjWidth+1)/2+THRD_SZ-1)/THRD_SZ
                );
        fThread = dim3(THRD_SZ,LYR_BLK);

        // use the last block to make frame zero.
        int temp = ((pConf->n+1)/2+TILE_SZ-1)/TILE_SZ;
        bGrid = dim3((1+temp)*temp/2);
        bThread = dim3(TILE_SZ*TILE_SZ, ANG_BLK);
    }

    cudaDeviceReset();
    HANDLE_ERROR(cudaMalloc((void**)&dev_img,pConf->imgSize*sizeof(ft)));
    HANDLE_ERROR(cudaMalloc((void**)&dev_sino,pConf->prjFull*pConf->prjWidth*sizeof(ft)));
    HANDLE_ERROR(cudaMemcpyToSymbol( dConf, pConf, sizeof(prjConf)) );

#if EXE_TIME
    // start the timers
    HANDLE_ERROR( cudaEventCreate( &start ) );
    HANDLE_ERROR( cudaEventCreate( &stop ) );
#endif
#if DEBUG
    printf("fGrid=(%d,%d), fThread=(%d,%d), bGrid=(%d,%d), bThread=(%d,%d)\n",
            fGrid.x,fGrid.y,fThread.x,fThread.y,
            bGrid.x,bGrid.y,bThread.x,bThread.y);
    printf("setup done\n");
#endif
}

void showSetup(){
    printf("config.n=%d\n",config.n);
    printf("config.prjWidth=%d\n",config.prjWidth);
    printf("config.np=%d\n",config.np);
    printf("config.prjFull=%d\n",config.prjFull);
    printf("config.dSize=%g\n",config.dSize);
    printf("config.effectiveRate=%g\n",config.effectiveRate);
    printf("config.d=%g\n",config.d);
}

#ifdef __cplusplus
extern "C"
#endif
void cleanUp(){
#if EXE_TIME
    HANDLE_ERROR( cudaEventDestroy( start ) );
    HANDLE_ERROR( cudaEventDestroy( stop ) );
#endif
    HANDLE_ERROR( cudaFree( dev_img ) );
    HANDLE_ERROR( cudaFree( dev_sino ) );
    cudaDeviceReset();
}

#ifdef __cplusplus
extern "C"
#endif
int gpuPrj(ft* img, ft* sino, char cmd){
#if EXE_PROF
    cudaProfilerStart();
#endif

#if EXE_TIME
    // start the timers
    HANDLE_ERROR( cudaEventRecord( start, 0 ) );
    HANDLE_ERROR( cudaEventSynchronize( start ) );
#endif

    if(cmd & FWD_BIT){
#if DEBUG
        printf("Forward projecting ...\n");
#endif
        HANDLE_ERROR(cudaMemcpy(dev_img, img, pConf->imgSize*sizeof(ft), 
                    cudaMemcpyHostToDevice ) );
        if(pConf->d>0){
#if DEBUG
        printf("Image copied to device ...\n");
        printf("calling rayDriveFan ...\n");
#endif
            rayDriveFan<<<fGrid,fThread>>>(dev_img, dev_sino);
        }else
            rayDrivePar<<<fGrid,fThread>>>(dev_img, dev_sino);
        HANDLE_ERROR( cudaMemcpy( sino, dev_sino, pConf->sinoSize*sizeof(ft),
                    cudaMemcpyDeviceToHost ) );

        if(pConf->prjWidth%2==0)
            for(int i=0,idx=0; i<pConf->np; i++,idx+=pConf->prjWidth)
                sino[idx]=0;
        
    }else if(cmd & BWD_BIT){
#if DEBUG
        printf("Backward projecting ...\n");
#endif
        HANDLE_ERROR(cudaMemcpy(dev_sino,sino,pConf->sinoSize*sizeof(ft),
                    cudaMemcpyHostToDevice ) );
        if(pConf->d>0)
            pixelDriveFan<<<bGrid,bThread>>>(dev_img, dev_sino,0);
        else
            pixelDrivePar<<<bGrid,bThread>>>(dev_img, dev_sino,0);
        HANDLE_ERROR( cudaMemcpy( img, dev_img, pConf->imgSize*sizeof(ft),
                    cudaMemcpyDeviceToHost ) );
        if(pConf->n%2==0){
            for(int i=0,idx=0; i<pConf->n; i++,idx+=pConf->n){
                img[i]=0; img[idx]=0;
            }
        }
    }else if(cmd & FBP_BIT){
#if DEBUG
        printf("Filtered Backprojecting ...\n");
#endif
        ft* pSino = (ft*) calloc(pConf->sinoSize,sizeof(ft));
        ft bq;
        int pC = pConf->prjWidth/2;

#if DEBUG
        FILE* f = fopen("sinogram_0.data","wb");
        fwrite(sino, sizeof(ft), config.sinoSize, f);
        fclose(f);
#endif

        if(pConf->d>0){
#if DEBUG
            printf("reconstructing by FBP (fan beam) ... \n");
#endif
            for(int j=0; j<(pConf->prjWidth+1)/2; j++){
                bq = sqrt(pConf->d*pConf->d + j*j*pConf->dSize*pConf->dSize);
                for(int i=0, idx1=pC-j, idx2=pC+j; i<pConf->np;
                        i++, idx1+=pConf->prjWidth, idx2+=pConf->prjWidth){
                    pSino[idx1]=sino[idx1]*pConf->d / bq;
                    pSino[idx2]=sino[idx2]*pConf->d / bq;
                }
            }
            if(pConf->prjWidth%2==0){
                bq = sqrt(pConf->d*pConf->d + pC*pC*pConf->dSize*pConf->dSize);
                for(int i=0, idx1=0; i<pConf->np;
                        i++, idx1+=pConf->prjWidth){
                    pSino[idx1]=sino[idx1]*pConf->d / bq;
                }
            }
        }else{
#if DEBUG
            printf("reconstructing by FBP (parallel beam) ... \n");
#endif
            memcpy(pSino,sino,pConf->sinoSize*sizeof(ft));
        }

#if DEBUG
        f = fopen("sinogram_1.data","wb");
        fwrite(pSino, sizeof(ft), config.sinoSize, f);
        fclose(f);
#endif

        for(int i=0; i<pConf->np; i++){
            rampFilter(pSino+i*pConf->prjWidth, pConf->prjWidth, pConf->dSize);
        }

#if DEBUG
        f = fopen("sinogram_2.data","wb");
        fwrite(pSino, sizeof(ft), config.sinoSize, f);
        fclose(f);
#endif
        HANDLE_ERROR(cudaMemcpy(dev_sino,pSino,pConf->sinoSize*sizeof(ft),
                    cudaMemcpyHostToDevice ) );
        if(pConf->d>0)
            pixelDriveFan<<<bGrid,bThread>>>(dev_img, dev_sino,1);
        else
            pixelDrivePar<<<bGrid,bThread>>>(dev_img, dev_sino,1);
        HANDLE_ERROR( cudaMemcpy( img, dev_img, pConf->imgSize*sizeof(ft),
                    cudaMemcpyDeviceToHost ) );

        if(pConf->n%2==0){
            for(int i=0,idx=0; i<pConf->n; i++,idx+=pConf->n){
                img[i]=0; img[idx]=0;
            }
        }
        free(pSino);
    }


#if EXE_PROF
    cudaProfilerStop();
#endif

#if EXE_TIME
    float elapsedTime;
    HANDLE_ERROR( cudaEventRecord( stop, 0 ) );
    HANDLE_ERROR( cudaEventSynchronize( stop ) );
    HANDLE_ERROR( cudaEventElapsedTime( &elapsedTime,
                start, stop ) );
    printf( "Time taken:  %3.1f ms\n", elapsedTime );
#endif
    //FILE* f = fopen("sinogram.data","wb");
    //fwrite(sino, sizeof(ft), pConf->sinoSize, f);
    //fclose(f);
    return 0;
}

int forwardTest( void ) {
#if SHOWIMG
    CPUBitmap image( config.n, config.n );
    unsigned char *ptr = image.get_ptr();
    CPUBitmap sinogram( config.prjWidth, config.np );
    unsigned char *sinoPtr = sinogram.get_ptr();
    unsigned char value;
#endif

    ft* img = (ft*) malloc(config.imgSize*sizeof(ft));
    ft *sino = (ft *) malloc(config.sinoSize*sizeof(ft));
    int offset;
    int YC = config.n/2, XC = config.n/2;
    for(int i=0; i < config.n; i++){
        for(int j=0; j < config.n; j++){
            offset = i*config.n+j;
            if(((i-YC-0.02*config.n)*(i-YC-0.02*config.n)+(j-XC-0)*(j-XC-0)<=(0.32*config.n)*(0.32*config.n))
                    && ((i-YC-0.12*config.n)*(i-YC-0.12*config.n)+
                        (j-XC-0.12*config.n)*(j-XC-0.12*config.n)>=(0.088*config.n)*(0.088*config.n))
              ){
                img[offset]=1;
            }else
                img[offset]=0;
            //            if(i<5 && j < 5) img[i][j]=1;
#if SHOWIMG
            value = (unsigned char)(0xff * img[offset]);
            offset = (config.n-1-i)*config.n+j;
            ptr[(offset<<2)+0] = value;
            ptr[(offset<<2)+1] = value;
            ptr[(offset<<2)+2] = value;
            ptr[(offset<<2)+3] = 0xff;
#endif
        }
    }
#if DEBUG
    FILE* f = fopen("img.data","w");
    fwrite(img,sizeof(ft), pConf->imgSize,f);
    fclose(f);
#endif
    //image.display_and_exit();

    gpuPrj(img, sino, RENEW_MEM | FWD_BIT);

#if DEBUG
    f = fopen("sinogram.data","wb");
    fwrite(sino, sizeof(ft), config.sinoSize, f);
    fclose(f);
#endif
#if SHOWIMG
    ft temp=0;
    for(int i=0; i < config.np; i++){
        for(int j=0; j < config.prjWidth; j++){
            offset = i*config.prjWidth+j;
            if( sino[offset]>temp)
                temp=sino[offset];
        }
    }
    for(int i=0; i < config.np; i++)
        for(int j=0; j < config.prjWidth; j++){
            offset = i*config.prjWidth+j;
            value = (unsigned char)(255 * sino[offset]/temp);
            offset = (config.np-1-i)*config.prjWidth+j;
            sinoPtr[(offset<<2)+0] = value;
            sinoPtr[(offset<<2)+1] = value;
            sinoPtr[(offset<<2)+2] = value;
            sinoPtr[(offset<<2)+3] = 0xff;
        }
#endif
    free(img); free(sino);

#if SHOWIMG
    //sinogram.display_and_exit();
#endif
    return 0;
}

int backwardTest( void ) {
#if SHOWIMG
    CPUBitmap image( config.n, config.n );
    unsigned char *ptr = image.get_ptr();
    CPUBitmap sinogram( config.prjWidth, config.np );
    unsigned char *sinoPtr = sinogram.get_ptr();
    unsigned char value;
#endif

    ft* img = (ft*) malloc(config.imgSize*sizeof(ft));
    ft *sino = (ft *) malloc(config.sinoSize*sizeof(ft));

#if DEBUG
    FILE* f = fopen("sinogram.data","rb");
    if(!fread(sino,sizeof(ft),config.sinoSize,f))
        perror("cannot read from sinogram.data\n");
    fclose(f);
#endif

    
    int tempI;
    tempI=rand()%config.np;
    tempI=0;
    for(int i=0; i < config.np; i++){
        for(int j=0; j < config.prjWidth; j++){
            tempI=sino[i*config.prjWidth+j]>tempI? sino[i*config.prjWidth+j] : tempI;
        }
    }
    for(int i=0; i < config.np; i++){
        for(int j=0; j < config.prjWidth; j++){
            int offset = i*config.prjWidth+j;
            //if(i==tempI*0 && abs(j-config.prjWidth/2)<=150){
            //    if(offset%15<6) sino[offset]=1;
            //    else sino[offset]=0;
            //}else
            //    sino[offset]=0;
            //tempI=1;

            //fscanf(f,"%f ", &sino[offset]);
            //            if(i<5 && j < 5) img[i][j]=1;
#if SHOWIMG
            value = (unsigned char)(255 * sino[offset]/tempI);
            offset = (config.np-1-i)*config.prjWidth+j;
            sinoPtr[(offset<<2)+0] = value;
            sinoPtr[(offset<<2)+1] = value;
            sinoPtr[(offset<<2)+2] = value;
            sinoPtr[(offset<<2)+3] = 0xff;
#endif
        }
        //fscanf(f,"\n");
    }
    //sinogram.display_and_exit();

    gpuPrj(img, sino, RENEW_MEM | BWD_BIT);

#if DEBUG
    f = fopen("reImg.data","wb");
    fwrite(img,sizeof(ft),config.imgSize,f);
    fclose(f);
#endif

#if SHOWIMG
    ft temp=0;
    for(int i=0; i < config.n; i++)
        for(int j=0; j < config.n; j++){
            int offset = i*config.n+j;
            if( img[offset]>temp) temp=img[offset];
        }
    //printf("temp=%g\n",temp);
    for(int i=0; i < config.n; i++){
        for(int j=0; j < config.n; j++){
            offset = i*config.n+j;
            if(img[offset]>0) value = (unsigned char)(255 * img[offset]/temp);
            else value = 0;
            offset = (config.n-1-i)*config.n+j;
            ptr[(offset<<2)+0] = value;
            ptr[(offset<<2)+1] = value;
            ptr[(offset<<2)+2] = value;
            ptr[(offset<<2)+3] = 0xff;
        }
    }
#endif

    free(sino); free(img);
#if SHOWIMG
    image.display_and_exit();
#endif
    return 0;
}

int main(int argc, char *argv[]){
    int N = 1024;
    if(argc>1){
        N = atoi(argv[1]);
        printf("N=%d\n",N);
    }

    setup(N,N,360,360,1,1,3*N);
    //showSetup();
    forwardTest();
    backwardTest();
    cleanUp();
    return 0;

    setup(N,N,180,360,1,1,0);
    showSetup();
    forwardTest();
    backwardTest();
    cleanUp();
    return 0;
}

