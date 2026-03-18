/**
 * Chapman Flare - Cyberpunk 2077 Style
 * =====================================
 * A screen-space pseudo lens flare based on John Chapman's technique,
 * tuned to emulate the look of Cyberpunk 2077's built-in lens flare.
 *
 * CP2077's implementation (per Froyok's reverse-engineering):
 *   - Ghosts + halo generated in a single feature pass at half res
 *   - 4-5 ghost samples along flipped UV vector through image centre
 *   - Halo via radial warp with normalised, fixed-length vector
 *   - Per-channel (RGB) chromatic offset for colour fringing
 *   - Gaussian blur to soften features
 *   - Additive composite
 *
 * Almost entirely generated code.
 */

// ============================================================================
// PREPROCESSOR
// ============================================================================

#ifndef CHAPMAN_FLARE_DOWNSCALE
    #define CHAPMAN_FLARE_DOWNSCALE 2
#endif

#ifndef CHAPMAN_FLARE_GHOST_COUNT
    #define CHAPMAN_FLARE_GHOST_COUNT 5
#endif

#ifndef CHAPMAN_FLARE_BLUR_SAMPLES
    #define CHAPMAN_FLARE_BLUR_SAMPLES 21
#endif

#ifndef CHAPMAN_FLARE_CHROMA_SAMPLES
    #define CHAPMAN_FLARE_CHROMA_SAMPLES 3
#endif

// ============================================================================
// INCLUDES
// ============================================================================

#include "ReShade.fxh"

// ============================================================================
// UNIFORMS
// ============================================================================

uniform float fThreshold <
    ui_type = "slider";
    ui_label = "Brightness Threshold";
    ui_tooltip = "Minimum brightness for a pixel to contribute to the flare.\n"
                 "Lower = more pixels contribute, higher = only bright highlights.\n"
                 "CP2077 uses a very low threshold with curve falloff.";
    ui_category = "Threshold";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.85;

uniform float fThresholdKnee <
    ui_type = "slider";
    ui_label = "Threshold Knee";
    ui_tooltip = "Softness of the threshold transition.\n"
                 "0 = hard cutoff, 1 = very gradual fade-in.";
    ui_category = "Threshold";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.5;

uniform float fGhostSpacing <
    ui_type = "slider";
    ui_label = "Ghost Spacing";
    ui_tooltip = "Distance between ghost samples along the flare axis.\n"
                 "Controls how spread out the repeated ghost blobs are.";
    ui_category = "Ghosts";
    ui_min = 0.05; ui_max = 1.5; ui_step = 0.01;
> = 0.30;

uniform float fGhostIntensity <
    ui_type = "slider";
    ui_label = "Ghost Intensity";
    ui_tooltip = "Brightness multiplier for the ghost features.";
    ui_category = "Ghosts";
    ui_min = 0.0; ui_max = 3.0; ui_step = 0.01;
> = 1.40;

uniform float fGhostFalloff <
    ui_type = "slider";
    ui_label = "Ghost Edge Falloff";
    ui_tooltip = "How quickly ghosts fade near screen edges.\n"
                 "Higher = ghosts only survive near the centre.";
    ui_category = "Ghosts";
    ui_min = 0.1; ui_max = 2.0; ui_step = 0.01;
> = 0.75;

uniform float fHaloRadius <
    ui_type = "slider";
    ui_label = "Halo Radius";
    ui_tooltip = "Radius of the halo ring effect.\n"
                 "Controls where the bright ring sits relative to image centre.";
    ui_category = "Halo";
    ui_min = 0.1; ui_max = 1.0; ui_step = 0.01;
> = 0.53;

uniform float fHaloThickness <
    ui_type = "slider";
    ui_label = "Halo Thickness";
    ui_tooltip = "Width of the halo ring. Lower = thinner ring.";
    ui_category = "Halo";
    ui_min = 0.01; ui_max = 0.5; ui_step = 0.01;
> = 0.15;

uniform float fHaloIntensity <
    ui_type = "slider";
    ui_label = "Halo Intensity";
    ui_tooltip = "Brightness multiplier for the halo ring.";
    ui_category = "Halo";
    ui_min = 0.0; ui_max = 3.0; ui_step = 0.01;
> = 1.0;

uniform float fHaloAspect <
    ui_type = "slider";
    ui_label = "Halo Aspect Correction";
    ui_tooltip = "Corrects the halo shape for screen aspect ratio.\n"
                 "0 = elliptical (matches screen), 1 = perfectly circular.";
    ui_category = "Halo";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;

uniform float fChromaShift <
    ui_type = "slider";
    ui_label = "Chromatic Aberration";
    ui_tooltip = "Base UV-space offset for RGB channel separation.\n"
                 "CP2077 uses very wide separation — the colour fringing\n"
                 "is often wider than the ghost blob itself.\n"
                 "This works in UV-space (0-1), not texel-space.";
    ui_category = "Chromatic Aberration";
    ui_min = 0.0; ui_max = 0.15; ui_step = 0.001;
> = 0.04;

uniform float fChromaRadialScale <
    ui_type = "slider";
    ui_label = "Radial Scaling";
    ui_tooltip = "How much the chromatic shift increases with distance from centre.\n"
                 "0 = uniform shift everywhere, 1 = shift scales linearly with radius.\n"
                 "CP2077's fringing grows significantly toward screen edges.";
    ui_category = "Chromatic Aberration";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
> = 1.0;

uniform float fBlurSigma <
    ui_type = "slider";
    ui_label = "Blur Sigma";
    ui_tooltip = "Gaussian blur sigma for softening flare features.\n"
                 "Higher = softer, more diffuse flare. Lower = sharper ghosts.";
    ui_category = "Blur";
    ui_min = 0.5; ui_max = 12.0; ui_step = 0.1;
> = 8.0;

uniform float fFlareIntensity <
    ui_type = "slider";
    ui_label = "Overall Intensity";
    ui_tooltip = "Master brightness multiplier for the entire flare effect.";
    ui_category = "Composite";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
> = 0.50;

uniform float fFlareSaturation <
    ui_type = "slider";
    ui_label = "Flare Saturation";
    ui_tooltip = "Colour saturation of the flare.\n"
                 "0 = monochrome flare, 1 = full colour, >1 = boosted colour.";
    ui_category = "Composite";
    ui_min = 0.0; ui_max = 5.0; ui_step = 0.01;
> = 5.0;

uniform float3 fFlareTint <
    ui_type = "color";
    ui_label = "Flare Tint";
    ui_tooltip = "Overall colour tint applied to the flare.\n"
                 "White = no tint (neutral).";
    ui_category = "Composite";
> = float3(1.0, 1.0, 1.0);

uniform bool bShowFlareOnly <
    ui_label = "Show Flare Only (Debug)";
    ui_tooltip = "Displays only the flare on a black background for tuning.";
    ui_category = "Debug";
> = false;

// ============================================================================
// TEXTURES & SAMPLERS
// ============================================================================

texture texFlareFeatures
{
    Width  = BUFFER_WIDTH / CHAPMAN_FLARE_DOWNSCALE;
    Height = BUFFER_HEIGHT / CHAPMAN_FLARE_DOWNSCALE;
    Format = RGBA16F;
};

texture texFlareBlurH
{
    Width  = BUFFER_WIDTH / CHAPMAN_FLARE_DOWNSCALE;
    Height = BUFFER_HEIGHT / CHAPMAN_FLARE_DOWNSCALE;
    Format = RGBA16F;
};

texture texFlareBlurV
{
    Width  = BUFFER_WIDTH / CHAPMAN_FLARE_DOWNSCALE;
    Height = BUFFER_HEIGHT / CHAPMAN_FLARE_DOWNSCALE;
    Format = RGBA16F;
};

sampler sBackBuffer    { Texture = ReShade::BackBufferTex; SRGBTexture = false; };
sampler sFlareFeatures { Texture = texFlareFeatures; };
sampler sFlareBlurH    { Texture = texFlareBlurH; };
sampler sFlareBlurV    { Texture = texFlareBlurV; };

// ============================================================================
// FUNCTIONS
// ============================================================================

float Luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float3 ApplyThreshold(float3 rgb, float threshold, float knee)
{
    float lum = Luminance(rgb);
    float t   = threshold;
    float k   = knee * threshold;

    float softT = t - k;
    float excess = lum - softT;

    if (excess <= 0.0)
        return float3(0.0, 0.0, 0.0);

    if (excess < 2.0 * k)
    {
        float w = excess / (2.0 * k + 1e-6);
        return rgb * (w * w);
    }

    return rgb * (1.0 - t / (lum + 1e-6));
}

float3 SampleChromatic(sampler s, float2 uv, float2 direction, float distFromCentre)
{
    float baseShift = fChromaShift;
    float radialMul = lerp(1.0, distFromCentre * 2.0, fChromaRadialScale);
    float totalShift = baseShift * radialMul;

    float2 shiftVec = direction * totalShift;

    float3 result = float3(0.0, 0.0, 0.0);
    float3 totalWeight = float3(0.0, 0.0, 0.0);

    for (int i = 0; i < CHAPMAN_FLARE_CHROMA_SAMPLES; i++)
    {
        float t = (float(i) / float(CHAPMAN_FLARE_CHROMA_SAMPLES - 1)) * 2.0 - 1.0;

        float2 offset = shiftVec * t;
        float3 tap = tex2Dlod(s, float4(uv + offset, 0, 0)).rgb;

        float3 w;
        w.r = saturate(1.0 - abs(t - (-0.667)) * 2.0);
        w.g = saturate(1.0 - abs(t) * 2.0);
        w.b = saturate(1.0 - abs(t - 0.667) * 2.0);

        w = pow(max(w, 0.0), 0.6);

        result += tap * w;
        totalWeight += w;
    }

    return result / max(totalWeight, float3(1e-6, 1e-6, 1e-6));
}

float WindowCubic(float x, float centre, float width)
{
    float d = abs(x - centre) / width;
    d = saturate(d);
    return 1.0 - d * d * (3.0 - 2.0 * d);
}

float GaussianWeight(int offset, float sigma)
{
    return exp(-0.5 * float(offset * offset) / (sigma * sigma));
}

// ============================================================================
// VERTEX SHADER
// ============================================================================

void VS_PostProcess(
    in  uint   id       : SV_VertexID,
    out float4 position : SV_Position,
    out float2 texcoord : TEXCOORD)
{
    texcoord.x = (id == 2) ? 2.0 : 0.0;
    texcoord.y = (id == 1) ? 2.0 : 0.0;
    position = float4(texcoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

// ============================================================================
// PASS 1: Feature Generation (Ghosts + Halo + Chromatic Aberration)
// ============================================================================

float4 PS_FeatureGeneration(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float aspectRatio = float(BUFFER_WIDTH) / float(BUFFER_HEIGHT);

    float2 flippedUV = float2(1.0, 1.0) - uv;

    float2 ghostVec = (float2(0.5, 0.5) - flippedUV) * fGhostSpacing;
    float2 direction = normalize(ghostVec);

    float3 result = float3(0.0, 0.0, 0.0);

    // --- GHOSTS ---
    for (int i = 0; i < CHAPMAN_FLARE_GHOST_COUNT; i++)
    {
        float2 sampleUV = frac(flippedUV + ghostVec * float(i));

        float d = distance(sampleUV, float2(0.5, 0.5));
        float weight = 1.0 - smoothstep(0.0, fGhostFalloff, d);

        float ghostHue = float(i) / float(CHAPMAN_FLARE_GHOST_COUNT);
        float3 ghostTint = float3(
            1.0 + 0.15 * sin(ghostHue * 6.283),
            1.0 + 0.10 * cos(ghostHue * 4.5),
            1.0 + 0.15 * sin(ghostHue * 3.0 + 1.5)
        );

        float3 s = SampleChromatic(sBackBuffer, sampleUV, direction, d);
        s = ApplyThreshold(s, fThreshold, fThresholdKnee);

        result += s * weight * ghostTint;
    }

    result *= fGhostIntensity / float(CHAPMAN_FLARE_GHOST_COUNT);

    // --- HALO ---
    float effectiveAspect = lerp(1.0, aspectRatio, fHaloAspect);

    float2 haloVec = float2(0.5, 0.5) - flippedUV;
    haloVec.x /= effectiveAspect;
    haloVec = normalize(haloVec);
    haloVec.x *= effectiveAspect;

    float2 correctedUV = (flippedUV - float2(0.5, 0.0)) / float2(effectiveAspect, 1.0) + float2(0.5, 0.0);
    float haloDist = distance(correctedUV, float2(0.5, 0.5));
    float haloWeight = WindowCubic(haloDist, fHaloRadius, fHaloThickness);

    float2 haloSampleUV = flippedUV + haloVec * fHaloRadius;
    haloSampleUV = clamp(haloSampleUV, 0.0, 1.0);

    float haloDistFromCentre = distance(haloSampleUV, float2(0.5, 0.5));
    float3 haloSample = SampleChromatic(sBackBuffer, haloSampleUV, haloVec, haloDistFromCentre);
    haloSample = ApplyThreshold(haloSample, fThreshold, fThresholdKnee);

    result += haloSample * haloWeight * fHaloIntensity;

    return float4(result, 1.0);
}

// ============================================================================
// PASS 2: Horizontal Gaussian Blur
// ============================================================================

float4 PS_BlurH(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float2 texelSize = float2(CHAPMAN_FLARE_DOWNSCALE, 0.0) / float2(BUFFER_WIDTH, BUFFER_HEIGHT);
    float3 result = float3(0.0, 0.0, 0.0);
    float  totalWeight = 0.0;

    int halfSamples = CHAPMAN_FLARE_BLUR_SAMPLES / 2;

    [unroll]
    for (int i = -halfSamples; i <= halfSamples; i++)
    {
        float w = GaussianWeight(i, fBlurSigma);
        result += tex2Dlod(sFlareFeatures, float4(uv + texelSize * float(i), 0, 0)).rgb * w;
        totalWeight += w;
    }

    return float4(result / totalWeight, 1.0);
}

// ============================================================================
// PASS 3: Vertical Gaussian Blur
// ============================================================================

float4 PS_BlurV(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float2 texelSize = float2(0.0, CHAPMAN_FLARE_DOWNSCALE) / float2(BUFFER_WIDTH, BUFFER_HEIGHT);
    float3 result = float3(0.0, 0.0, 0.0);
    float  totalWeight = 0.0;

    int halfSamples = CHAPMAN_FLARE_BLUR_SAMPLES / 2;

    [unroll]
    for (int i = -halfSamples; i <= halfSamples; i++)
    {
        float w = GaussianWeight(i, fBlurSigma);
        result += tex2Dlod(sFlareBlurH, float4(uv + texelSize * float(i), 0, 0)).rgb * w;
        totalWeight += w;
    }

    return float4(result / totalWeight, 1.0);
}

// ============================================================================
// PASS 4: Composite
// ============================================================================

float4 PS_Composite(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float3 scene = tex2D(sBackBuffer, uv).rgb;
    float3 flare = tex2D(sFlareBlurV, uv).rgb;

    // Saturation
    float flareLum = Luminance(flare);
    flare = lerp(float3(flareLum, flareLum, flareLum), flare, fFlareSaturation);

    // Tint
    flare *= fFlareTint;

    // Intensity
    flare *= fFlareIntensity;

    if (bShowFlareOnly)
        return float4(flare, 1.0);

    return float4(scene + flare, 1.0);
}

// ============================================================================
// TECHNIQUE
// ============================================================================

technique ChapmanFlare <
    ui_label = "Chapman Flare (CP2077 Style)";
    ui_tooltip = "Screen-space pseudo lens flare based on John Chapman's technique,\n"
                 "tuned to emulate Cyberpunk 2077's built-in lens flare.\n\n"
                 "Features: ghosts, halo, chromatic aberration,\n"
                 "Gaussian blur, per-ghost spectral tinting.\n\n"
                 "Place BEFORE tonemapping shaders if possible for best results.";
>
{
    pass FeatureGeneration
    {
        VertexShader  = VS_PostProcess;
        PixelShader   = PS_FeatureGeneration;
        RenderTarget  = texFlareFeatures;
    }
    pass BlurHorizontal
    {
        VertexShader  = VS_PostProcess;
        PixelShader   = PS_BlurH;
        RenderTarget  = texFlareBlurH;
    }
    pass BlurVertical
    {
        VertexShader  = VS_PostProcess;
        PixelShader   = PS_BlurV;
        RenderTarget  = texFlareBlurV;
    }
    pass Composite
    {
        VertexShader  = VS_PostProcess;
        PixelShader   = PS_Composite;
    }
}
