/*
 * ====================================================================
 *
 *       Filename:  parFwdPrj.c
 *
 *    Description:  mexFunction to calculate parallel fwd projection
 *
 *        Version:  1.0
 *        Created:  09/12/2012 09:49:21 PM
 *       Revision:  none
 *       Compiler:  gcc
 *
 *         Author:  Renliang Gu (), renliang@iastate.edu
 *   Organization:  Iowa State University
 *
 * ====================================================================
 */
#include "mex.h"
#include <limits.h>
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include "prj.h"

#ifdef __cplusplus
extern "C" {
#endif
extern struct prjConf* pConf;
#ifdef __cplusplus
}
#endif

ft* img;
ft* sino;

/*  The gateway function */
void mexFunction( int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    double *img_double, *sino_double;
    float *img_float, *sino_float;
    //double *maskIdx;
    char* cmd;
    if(nrhs!=3){
        mexPrintf("number of input arguments are: %d\n",nrhs);
        return;
    }
    cmd=mxArrayToString(prhs[2]);

    if(!strcmp(cmd,"config")){
        struct prjConf config;
        config.n=mxGetScalar(mxGetField(prhs[1],0,"n"));
        config.prjWidth=mxGetScalar(mxGetField(prhs[1],0,"prjWidth"));
        config.np=mxGetScalar(mxGetField(prhs[1],0,"np"));
        config.prjFull=mxGetScalar(mxGetField(prhs[1],0,"prjFull"));
        config.dSize=(float)mxGetScalar(mxGetField(prhs[1],0,"dSize"));
        config.effectiveRate=(float)mxGetScalar(mxGetField(prhs[1],0,"effectiveRate"));
        config.d=(float)mxGetScalar(mxGetField(prhs[1],0,"d"));
#if DEBUG
        mexPrintf("\nConfiguring the operator...\n");
        mexPrintf("config.n=%d\n",config.n);
        mexPrintf("config.prjWidth=%d\n",config.prjWidth);
        mexPrintf("config.np=%d\n",config.np);
        mexPrintf("config.prjFull=%d\n",config.prjFull);
        mexPrintf("config.dSize=%g\n",config.dSize);
        mexPrintf("config.effectiveRate=%g\n",config.effectiveRate);
        mexPrintf("config.d=%g\n",config.d);
#endif
        setup(config.n, config.prjWidth, config.np, config.prjFull, config.dSize, config.effectiveRate, config.d);

        if(img!=NULL) free(img);
        if(sino!=NULL) free(sino);
        img=(ft*)malloc(pConf->imgSize*sizeof(ft));
        sino=(ft*)malloc(pConf->sinoSize*sizeof(ft));
    }else{
        if(!strcmp(cmd,"forward")){      /* forward projection */
            plhs[0] = mxCreateNumericMatrix(pConf->prjWidth*pConf->np,1,mxDOUBLE_CLASS,mxREAL);
            sino_double = mxGetPr(plhs[0]);

            if(mxIsDouble(prhs[0])){
                img_double = mxGetPr(prhs[0]);
                /* matrix transpose */
                for(int j=0; j<pConf->n; j++)
                    for(int i=0; i<pConf->n; i++)
                        img[i*pConf->n+j]=(ft)img_double[i+j*pConf->n];
#if DEBUG
                {
                    FILE* f = fopen("img_mPrj_1.data","wb");
                    fwrite(img, sizeof(ft), pConf->imgSize, f);
                    fclose(f);
                    f=fopen("img_mPrj_2.data","wb");
                    fwrite(img_double, sizeof(double), pConf->imgSize, f);
                    fclose(f);
                }
#endif
            }else if(mxIsSingle(prhs[0])){
                img_float = (float*)mxGetData(prhs[0]);
                /* matrix transpose */
                for(int j=0; j<pConf->n; j++)
                    for(int i=0; i<pConf->n; i++)
                        img[i*pConf->n+j]=(ft)img_float[i+j*pConf->n];
            }else{
                mexPrintf("unknown input parameter type in mPrj forward\n");
                return;
            }
#if GPU
            gpuPrj(img, sino, FWD_BIT);
#else
            cpuPrj(img, sino, FWD_BIT);
#endif
            for(int i=0; i<pConf->sinoSize; i++)
                sino_double[i]=sino[i];
        }else if(!strcmp(cmd,"backward")){
            plhs[0] = mxCreateNumericMatrix(pConf->n*pConf->n,1,mxDOUBLE_CLASS,mxREAL);
            img_double = mxGetPr(plhs[0]);

            if(mxIsDouble(prhs[0])){
                sino_double = mxGetPr(prhs[0]);
                for(int i=0; i<pConf->sinoSize; i++)
                    sino[i]=(ft)sino_double[i];
            }else if(mxIsSingle(prhs[0])){
                sino_float = (float*)mxGetData(prhs[0]);
                for(int i=0; i<pConf->sinoSize; i++)
                    sino[i]=(ft)sino_float[i];
            }else{
                mexPrintf("unknown input parameter type in mPrj backward\n");
                return;
            }

#if GPU
            gpuPrj(img, sino, BWD_BIT );
#else
            cpuPrj(img, sino, BWD_BIT );
#endif
            for(int j=0; j<pConf->n; j++)
                for(int i=0; i<pConf->n; i++)
                    img_double[i*pConf->n+j]=img[i+j*pConf->n];
        }else if(!strcmp(cmd,"FBP")){
            plhs[0] = mxCreateNumericMatrix(pConf->n*pConf->n,1,mxDOUBLE_CLASS,mxREAL);
            img_double = mxGetPr(plhs[0]);
            if(mxIsDouble(prhs[0])){
                sino_double = mxGetPr(prhs[0]);
                for(int i=0; i<pConf->sinoSize; i++)
                    sino[i]=(ft)sino_double[i];
            }else if(mxIsSingle(prhs[0])){
                sino_float = (float*)mxGetData(prhs[0]);
                for(int i=0; i<pConf->sinoSize; i++)
                    sino[i]=(ft)sino_float[i];
            }else{
                mexPrintf("unknown input parameter type in mPrj backward\n");
                return;
            }
#if GPU
            gpuPrj(img, sino, FBP_BIT );
#else
            cpuPrj(img, sino, FBP_BIT );
#endif
            for(int j=0; j<pConf->n; j++)
                for(int i=0; i<pConf->n; i++)
                    img_double[i*pConf->n+j]=img[i+j*pConf->n];
        }else{
            showSetup();
            mexPrintf("\nPrinting the current configuration ...\n");
            mexPrintf("config.n=%d\n",pConf->n);
            mexPrintf("config.prjWidth=%d\n",pConf->prjWidth);
            mexPrintf("config.np=%d\n",pConf->np);
            mexPrintf("config.prjFull=%d\n",pConf->prjFull);
            mexPrintf("config.dSize=%g\n",pConf->dSize);
            mexPrintf("config.effectiveRate=%g\n",pConf->effectiveRate);
            mexPrintf("config.d=%g\n",pConf->d);
        }
    }
    return;
}

