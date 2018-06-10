// This file is subject to the MIT License as seen in the root of this folder structure (LICENSE)

Shader "Ocean/Ocean"
{
	Properties
	{
		[Toggle] _ApplyNormalMapping("Apply Normal Mapping", Float) = 1
		[NoScaleOffset] _Normals ( "Normals", 2D ) = "bump" {}
		_NormalsStrength("Normals Strength", Range(0.0, 2.0)) = 0.3
		_NormalsScale("Normals Scale", Range(0.0, 50.0)) = 1.0
		[NoScaleOffset] _Skybox ("Skybox", CUBE) = "" {}
		_Diffuse("Diffuse", Color) = (0.2, 0.05, 0.05, 1.0)
		[Toggle] _ComputeDirectionalLight("Add Directional Light", Float) = 1
		_DirectionalLightFallOff("Directional Light Fall-Off", Range(1.0, 512.0)) = 128.0
		_DirectionalLightBoost("Directional Light Boost", Range(0.0, 16.0)) = 5.0
		[Toggle] _SubSurfaceScattering("Sub-Surface Scattering", Float) = 1
		_SubSurfaceColour("Sub-Surface Scattering Colour", Color) = (0.0, 0.48, 0.36, 1.)
		_SubSurfaceBase("Sub-Surface Scattering Base Mul", Range(0.0, 2.0)) = 0.6
		_SubSurfaceSun("Sub-Surface Scattering Sun Mul", Range(0.0, 10.0)) = 0.8
		_SubSurfaceSunFallOff("Sub-Surface Scattering Sun Fall-Off", Range(1.0, 16.0)) = 4.0
		[Toggle] _Foam("Foam", Float) = 1
		[NoScaleOffset] _FoamTexture ( "Foam Texture", 2D ) = "white" {}
		_FoamScale("Foam Scale", Range(0.0, 50.0)) = 10.0
		_FoamWhiteColor("White Foam Color", Color) = (1.0, 1.0, 1.0, 1.0)
		_FoamBubbleColor("Bubble Foam Color", Color) = (0.0, 0.0904, 0.105, 1.0)
		_ShorelineFoamMinDepth("Shoreline Foam Min Depth", Range(0.0, 5.0)) = 0.27
		_ShorelineFoamMaxDepth("Shoreline Foam Max Depth", Range(0.0,10.0)) = 1.5
		_WaveFoamStart("Wave Foam Start", Range(0.0, 2.0)) = 0.0
		_WaveFoamStrength("Wave Foam Strength", Range(0.0, 2.0)) = 1.0
		_WaveFoamFeather("Wave Foam Feather", Range(0.001, 1.0)) = 0.32
		_WaveFoamBubblesStrength("Wave Foam Bubbles Strength", Range(0.0, 1.0)) = 0.637
		_WaveFoamBubblesStart("Wave Foam Bubbles Start", Range(0.0, 2.0)) = 0.115
		_WaveFoamLightScale("Wave Foam Light Scale", Range(0.0, 2.0)) = 0.7
		_WaveFoamNormalsY("Wave Foam Normal Y Component", Range(0.0, 0.5)) = 0.5
		[Toggle] _Foam3DLighting("Foam 3D Lighting", Float) = 1
		[Toggle] _Transparency("Transparency", Float) = 1
		_DepthFogDensity("Depth Fog Density", Vector) = (0.28, 0.16, 0.24, 1.0)
		_FresnelPower("Fresnel Power", Range(0.0,20.0)) = 3.0
		[Toggle] _DebugDisableShapeTextures("Debug Disable Shape Textures", Float) = 0
		[Toggle] _DebugVisualiseShapeSample("Debug Visualise Shape Sample", Float) = 0
		[Toggle] _DebugDisableSmoothLOD("Debug Disable Smooth LOD", Float) = 0
		[Toggle] _CompileShaderWithDebugInfo("Compile Shader With Debug Info (D3D11)", Float) = 0
	}

	Category
	{
		Tags {}

		SubShader
		{
			// this sorts back to front due to transparent i guess, perhaps set queue to Geometry+1?
			Tags { "LightMode"="ForwardBase" "Queue"="Transparent" "IgnoreProjector"="True" "RenderType"="Opaque" }

			GrabPass
			{
				"_BackgroundTexture"
			}

			Pass
			{
				CGPROGRAM
				#pragma vertex vert
				#pragma fragment frag
				#pragma multi_compile_fog
				#pragma shader_feature _APPLYNORMALMAPPING_ON
				#pragma shader_feature _COMPUTEDIRECTIONALLIGHT_ON
				#pragma shader_feature _SUBSURFACESCATTERING_ON
				#pragma shader_feature _TRANSPARENCY_ON
				#pragma shader_feature _FOAM_ON
				#pragma shader_feature _FOAM3DLIGHTING_ON
				#pragma shader_feature _DEBUGDISABLESHAPETEXTURES_ON
				#pragma shader_feature _DEBUGVISUALISESHAPESAMPLE_ON
				#pragma shader_feature _DEBUGDISABLESMOOTHLOD_ON
				#pragma shader_feature _COMPILESHADERWITHDEBUGINFO_ON

				#if _COMPILESHADERWITHDEBUGINFO_ON
				#pragma enable_d3d11_debug_symbols
				#endif

				#include "UnityCG.cginc"
				#include "TextureBombing.cginc"

				#define DEPTH_BIAS 100.

				struct appdata_t
				{
					float4 vertex : POSITION;
					float2 texcoord: TEXCOORD0;
				};

				struct v2f
				{
					float4 vertex : SV_POSITION;
					half3 n : TEXCOORD1;
					half4 shorelineFoam_screenPos : TEXCOORD4;
					half4 foam_lodAlpha_worldXZUndisplaced : TEXCOORD5;
					float3 worldPos : TEXCOORD7;
					#if _DEBUGVISUALISESHAPESAMPLE_ON
					half3 debugtint : TEXCOORD8;
					#endif
					half4 grabPos : TEXCOORD9;

					UNITY_FOG_COORDS( 3 )
				};

				// GLOBAL PARAMS

				#include "OceanLODData.cginc"

				uniform float3 _OceanCenterPosWorld;
				uniform half _ShorelineFoamMaxDepth;

				// INSTANCE PARAMS

				// Geometry data
				// x: A square is formed by 2 triangles in the mesh. Here x is square size
				// yz: normalScrollSpeed0, normalScrollSpeed1
				// w: Geometry density - side length of patch measured in squares
				uniform float4 _GeomData;

				// MeshScaleLerp, FarNormalsWeight, LODIndex (debug), unused
				uniform float4 _InstanceData;

				// sample wave or terrain height, with smooth blend towards edges.
				// would equally apply to heights instead of displacements.
				// this could be optimized further.
				void SampleDisplacements( in sampler2D i_dispSampler, in sampler2D i_oceanDepthSampler, in float2 i_centerPos, in float i_res, in float i_invRes, in float i_texelSize, in float2 i_samplePos, in float wt, inout float3 io_worldPos, inout float3 io_n, inout float io_foam, inout half io_shorelineFoam )
				{
					if( wt < 0.001 )
						return;

					float4 uv = float4(WD_worldToUV(i_samplePos, i_centerPos, i_res, i_texelSize), 0., 0.);

					// do computations for hi-res
					float3 dd = float3(i_invRes, 0.0, i_texelSize);
					half4 s = tex2Dlod(i_dispSampler, uv);
					half3 sx = tex2Dlod(i_dispSampler, uv + dd.xyyy).xyz;
					half3 sz = tex2Dlod(i_dispSampler, uv + dd.yxyy).xyz;
					half3 disp = s.xyz;
					half3 disp_x = dd.zyy + sx;
					half3 disp_z = dd.yyz + sz;

					io_worldPos += wt * disp;
					io_foam += wt * s.a;

					float3 n = normalize( cross( disp_z - disp, disp_x - disp ) );
					io_n.xz += wt * n.xz;

					// foam from shallow water - signed depth is depth compared to sea level, plus wave height. depth bias is an optimisation
					// which allows the depth data to be initialised once to 0 without generating foam everywhere.
					half signedDepth = (tex2Dlod(i_oceanDepthSampler, uv).x + DEPTH_BIAS) + disp.y ;
					io_shorelineFoam += wt * clamp( 1. - signedDepth / _ShorelineFoamMaxDepth, 0., 1.);
				}

				v2f vert( appdata_t v )
				{
					v2f o;

					// see comments above on _GeomData
					const float SQUARE_SIZE = _GeomData.x, SQUARE_SIZE_2 = 2.0*_GeomData.x, SQUARE_SIZE_4 = 4.0*_GeomData.x;
					const float BASE_DENSITY = _GeomData.w;

					// move to world
					o.worldPos = mul( unity_ObjectToWorld, v.vertex );
	
					// snap the verts to the grid
					// The snap size should be twice the original size to keep the shape of the eight triangles (otherwise the edge layout changes).
					o.worldPos.xz -= frac(_OceanCenterPosWorld.xz / SQUARE_SIZE_2) * SQUARE_SIZE_2; // caution - sign of frac might change in non-hlsl shaders
	
					// how far are we into the current LOD? compute by comparing the desired square size with the actual square size
					float2 offsetFromCenter = float2( abs( o.worldPos.x - _OceanCenterPosWorld.x ), abs( o.worldPos.z - _OceanCenterPosWorld.z ) );
					float taxicab_norm = max( offsetFromCenter.x, offsetFromCenter.y );
					float idealSquareSize = taxicab_norm / BASE_DENSITY;
					// interpolation factor to next lod (lower density / higher sampling period)
					float lodAlpha = idealSquareSize/SQUARE_SIZE - 1.0;
					// lod alpha is remapped to ensure patches weld together properly. patches can vary significantly in shape (with
					// strips added and removed), and this variance depends on the base density of the mesh, as this defines the strip width.
					// using .15 as black and .85 as white should work for base mesh density as low as 16. TODO - make this automatic?
					const float BLACK_POINT = 0.15, WHITE_POINT = 0.85;
					lodAlpha = max( (lodAlpha - BLACK_POINT) / (WHITE_POINT-BLACK_POINT), 0. );
					// blend out lod0 when viewpoint gains altitude
					lodAlpha = min(lodAlpha + _InstanceData.x, 1.);
					#if _DEBUGDISABLESMOOTHLOD_ON
					lodAlpha = 0.;
					#endif
					// pass it to fragment shader - used to blend normals scales
					o.foam_lodAlpha_worldXZUndisplaced.y = lodAlpha;


					// now smoothly transition vert layouts between lod levels - move interior verts inwards towards center
					float2 m = frac( o.worldPos.xz / SQUARE_SIZE_4 ); // this always returns positive
					float2 offset = m - 0.5;
					// check if vert is within one square from the center point which the verts move towards
					const float minRadius = 0.26; //0.26 is 0.25 plus a small "epsilon" - should solve numerical issues
					if( abs( offset.x ) < minRadius ) o.worldPos.x += offset.x * lodAlpha * SQUARE_SIZE_4;
					if( abs( offset.y ) < minRadius ) o.worldPos.z += offset.y * lodAlpha * SQUARE_SIZE_4;
					o.foam_lodAlpha_worldXZUndisplaced.zw = o.worldPos.xz;


					// sample shape textures - always lerp between 2 scales, so sample two textures
					o.n = half3(0., 1., 0.);
					o.foam_lodAlpha_worldXZUndisplaced.x = 0.;
					o.shorelineFoam_screenPos.x = 0.;
					// sample weights. params.z allows shape to be faded out (used on last lod to support pop-less scale transitions)
					float wt_0 = (1. - lodAlpha) * _WD_Params_0.z;
					float wt_1 = (1. - wt_0) * _WD_Params_1.z;
					// sample displacement textures, add results to current world pos / normal / foam
					#if !_DEBUGDISABLESHAPETEXTURES_ON
					const float2 wxz = o.worldPos.xz;
					SampleDisplacements( _WD_Sampler_0, _WD_OceanDepth_Sampler_0, _WD_Pos_0, _WD_Params_0.y, _WD_Params_0.w, _WD_Params_0.x, wxz, wt_0, o.worldPos, o.n, o.foam_lodAlpha_worldXZUndisplaced.x, o.shorelineFoam_screenPos.x);
					SampleDisplacements( _WD_Sampler_1, _WD_OceanDepth_Sampler_1, _WD_Pos_1, _WD_Params_1.y, _WD_Params_1.w, _WD_Params_1.x, wxz, wt_1, o.worldPos, o.n, o.foam_lodAlpha_worldXZUndisplaced.x, o.shorelineFoam_screenPos.x);
					#endif

					// debug tinting to see which shape textures are used
					#if _DEBUGVISUALISESHAPESAMPLE_ON
					#define TINT_COUNT (uint)7
					half3 tintCols[TINT_COUNT]; tintCols[0] = half3(1., 0., 0.); tintCols[1] = half3(1., 1., 0.); tintCols[2] = half3(1., 0., 1.); tintCols[3] = half3(0., 1., 1.); tintCols[4] = half3(0., 0., 1.); tintCols[5] = half3(1., 0., 1.); tintCols[6] = half3(.5, .5, 1.);
					o.debugtint = wt_0 * tintCols[_WD_LodIdx_0 % TINT_COUNT] + wt_1 * tintCols[_WD_LodIdx_1 % TINT_COUNT];
					#endif


					// view-projection	
					o.vertex = mul(UNITY_MATRIX_VP, float4(o.worldPos, 1.));

					UNITY_TRANSFER_FOG(o, o.vertex);

					// unfortunate hoop jumping - this is inputs for refraction. depending on whether HDR is on or off, the grabbed scene
					// colours may or may not come from the backbuffer, which means they may or may not be flipped in y. use these macros
					// to get the right results, every time.
					o.grabPos = ComputeGrabScreenPos(o.vertex);
					o.shorelineFoam_screenPos.yzw = ComputeScreenPos(o.vertex).xyw;

					return o;
				}

				// frag shader uniforms
				uniform half4 _Diffuse;
				uniform half _DirectionalLightFallOff;
				uniform half _DirectionalLightBoost;

				uniform half4 _SubSurfaceColour;
				uniform half _SubSurfaceBase;
				uniform half _SubSurfaceSun;
				uniform half _SubSurfaceSunFallOff;

				uniform half4 _DepthFogDensity;
				uniform samplerCUBE _Skybox;

				uniform sampler2D _FoamTexture;
				uniform float4 _FoamTexture_TexelSize;
				uniform half4 _FoamWhiteColor;
				uniform half4 _FoamBubbleColor;
				uniform half _ShorelineFoamMinDepth;
				uniform half _WaveFoamStrength, _WaveFoamStart, _WaveFoamFeather;
				uniform half _WaveFoamBubblesStrength, _WaveFoamBubblesStart;
				uniform half _WaveFoamNormalsY;
				uniform half _WaveFoamLightScale;

				uniform sampler2D _Normals;
				uniform half _NormalsStrength;
				uniform half _NormalsScale;
				uniform half _FoamScale;
				uniform half _FresnelPower;
				uniform float _MyTime;
				uniform fixed4 _LightColor0;
				uniform half2 _WindDirXZ;

				// these are copied from the render target by unity
				sampler2D _BackgroundTexture;
				sampler2D _CameraDepthTexture;

				void ApplyNormalMaps(float2 worldXZUndisplaced, float lodAlpha, inout half3 io_n )
				{
					const float2 v0 = float2(0.94, 0.34), v1 = float2(-0.85, -0.53);
					const float geomSquareSize = _GeomData.x;
					float nstretch = _NormalsScale * geomSquareSize; // normals scaled with geometry
					const float spdmulL = _GeomData.y;
					half2 norm =
						UnpackNormal(tex2D( _Normals, (v0*_MyTime*spdmulL + worldXZUndisplaced) / nstretch )).xy +
						UnpackNormal(tex2D( _Normals, (v1*_MyTime*spdmulL + worldXZUndisplaced) / nstretch )).xy;

					// blend in next higher scale of normals to obtain continuity
					const float farNormalsWeight = _InstanceData.y;
					const half nblend = lodAlpha * farNormalsWeight;
					if( nblend > 0.001 )
					{
						// next lod level
						nstretch *= 2.;
						const float spdmulH = _GeomData.z;
						norm = lerp( norm,
							UnpackNormal(tex2D( _Normals, (v0*_MyTime*spdmulH + worldXZUndisplaced) / nstretch )).xy +
							UnpackNormal(tex2D( _Normals, (v1*_MyTime*spdmulH + worldXZUndisplaced) / nstretch )).xy,
							nblend );
					}

					// approximate combine of normals. would be better if normals applied in local frame.
					io_n.xz += _NormalsStrength * norm;
					io_n = normalize(io_n);
				}

				half3 AmbientLight()
				{
					return half3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w);
				}

				void ComputeFoam(half i_foam, float2 i_worldXZUndisplaced, float2 i_worldXZ, half3 i_n, half i_shorelineFoam, float i_pixelZ, float i_sceneZ, half3 i_view, float3 i_lightDir, out half3 o_bubbleCol, out half4 o_whiteFoamCol)
				{
					// Additive underwater foam
					float2 foamUVBubbles = (lerp(i_worldXZUndisplaced, i_worldXZ, 0.5) + 0.5 * _MyTime * _WindDirXZ) / _FoamScale;
					foamUVBubbles += 0.25 * i_n.xz;
					half bubbleFoamTexValue = texture(_FoamTexture, .37 * foamUVBubbles - .1*i_view.xz / i_view.y).r;
					half bubbleFoam = bubbleFoamTexValue * _WaveFoamBubblesStrength * saturate(i_foam - _WaveFoamBubblesStart);
					o_bubbleCol = bubbleFoam * _FoamBubbleColor.rgb * (AmbientLight() + _LightColor0);

					// White foam on top, with black-point fading
					half whiteFoam = _WaveFoamStrength * saturate(i_foam - _WaveFoamStart);
					// Shoreline foam
					whiteFoam += i_shorelineFoam;
					// feather foam very close to shore
					whiteFoam *= saturate((i_sceneZ - i_pixelZ) / _ShorelineFoamMinDepth);
					float2 foamUV = (i_worldXZUndisplaced + 0.5 * _MyTime * _WindDirXZ) / _FoamScale + 0.02 * i_n.xz;
					half foamTexValue = texture(_FoamTexture, foamUV).r;
					whiteFoam = foamTexValue * (smoothstep(whiteFoam + _WaveFoamFeather, whiteFoam, 1. - foamTexValue)) * _FoamWhiteColor.a;

					#if _FOAM3DLIGHTING_ON
					// Scale up delta by Z - keeps 3d look better at distance. better way to do this?
					float2 dd = float2(0.25 * i_pixelZ * _FoamTexture_TexelSize.x, 0.);
					half foamTexValue_x = texture(_FoamTexture, foamUV + dd.xy).r;
					half foamTexValue_z = texture(_FoamTexture, foamUV + dd.yx).r;
					half whiteFoam_x = foamTexValue_x * (smoothstep(whiteFoam + _WaveFoamFeather, whiteFoam, 1. - foamTexValue_x)) * _FoamWhiteColor.a;
					half whiteFoam_z = foamTexValue_z * (smoothstep(whiteFoam + _WaveFoamFeather, whiteFoam, 1. - foamTexValue_z)) * _FoamWhiteColor.a;

					// compute a foam normal that is rounded at the edge
					half sqrt_foam = sqrt(whiteFoam);
					half dfdx = sqrt(whiteFoam_x) - sqrt_foam, dfdz = sqrt(whiteFoam_z) - sqrt_foam;
					half3 fN = normalize(half3(-dfdx, _WaveFoamNormalsY, -dfdz));
					half foamNdL = max(0., dot(fN, i_lightDir));
					o_whiteFoamCol.rgb = _FoamWhiteColor.rgb * (AmbientLight() + _WaveFoamLightScale * _LightColor0 * foamNdL);
					#else // _FOAM3DLIGHTING_ON
					o_whiteFoamCol.rgb = _FoamWhiteColor.rgb * (AmbientLight() + _WaveFoamLightScale * _LightColor0);
					#endif // _FOAM3DLIGHTING_ON

					o_whiteFoamCol.a = min(2. * whiteFoam, 1.);
				}

				float3 WorldSpaceLightDir(float3 worldPos)
				{
					float3 lightDir = _WorldSpaceLightPos0.xyz;
					if (_WorldSpaceLightPos0.w > 0.)
					{
						// non-directional light - this is a position, not a direction
						lightDir = normalize(lightDir - worldPos.xyz);
					}
					return lightDir;
				}

				half3 OceanEmission(half3 view, half3 n, half3 n_geom, float3 lightDir, half4 grabPos, half3 screenPos, float pixelZ, half2 uvDepth, float sceneZ, half3 bubbleCol)
				{
					// use the constant layer of SH stuff - this is the average. it seems to give the right kind of colour
					half3 col = _Diffuse * half3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w);

					#if _SUBSURFACESCATTERING_ON
					// Approximate subsurface scattering - add light when surface faces viewer. Use geometry normal - don't need high freqs.
					half towardsSun = pow(max(0., dot(lightDir, -view)), _SubSurfaceSunFallOff);
					col += (_SubSurfaceBase + _SubSurfaceSun * towardsSun) * max(dot(n_geom, view), 0.) * _SubSurfaceColour * _LightColor0;
					#endif

					col += bubbleCol;

					#if _TRANSPARENCY_ON
					half2 uvBackgroundRefract = grabPos.xy / grabPos.w + .02 * n.xz;
					half2 uvDepthRefract = uvDepth +.02 * n.xz;
					half3 alpha = (half3)1.;

					// if we haven't refracted onto a surface in front of the water surface, compute an alpha based on Z delta
					if (sceneZ > pixelZ)
					{
						float sceneZRefract = LinearEyeDepth(texture(_CameraDepthTexture, uvDepthRefract).x);
						float maxZ = max(sceneZ, sceneZRefract);
						float deltaZ = maxZ - pixelZ;
						alpha = 1. - exp(-_DepthFogDensity.xyz * deltaZ);
					}

					half3 sceneColour = texture(_BackgroundTexture, uvBackgroundRefract).rgb;
					col = lerp(sceneColour, col, alpha);
					#endif

					return col;
				}

				half3 frag(v2f i) : SV_Target
				{
					half3 view = normalize(_WorldSpaceCameraPos - i.worldPos);

					// water surface depth, and underlying scene opaque surface depth
					float pixelZ = LinearEyeDepth(i.vertex.z);
					half3 screenPos = i.shorelineFoam_screenPos.yzw;
					half2 uvDepth = screenPos.xy / screenPos.z;
					float sceneZ = LinearEyeDepth(texture(_CameraDepthTexture, uvDepth).x);

					// could be per-vertex i reckon
					float3 lightDir = WorldSpaceLightDir(i.worldPos);

					// Normal - geom + normal mapping
					half3 n_geom = normalize(i.n);
					half3 n_pixel = n_geom;
					#if _APPLYNORMALMAPPING_ON
					ApplyNormalMaps(i.foam_lodAlpha_worldXZUndisplaced.zw, i.foam_lodAlpha_worldXZUndisplaced.y, n_pixel);
					#endif

					// Foam - underwater bubbles and whitefoam
					half3 bubbleCol = (half3)0.;
					#if _FOAM_ON
					half4 whiteFoamCol;
					ComputeFoam(i.foam_lodAlpha_worldXZUndisplaced.x, i.foam_lodAlpha_worldXZUndisplaced.zw, i.worldPos.xz, n_pixel, i.shorelineFoam_screenPos.x, pixelZ, sceneZ, view, lightDir, bubbleCol, whiteFoamCol);
					#endif

					// Compute color of ocean - in-scattered light + refracted scene
					half3 col = OceanEmission(view, n_pixel, n_geom, lightDir, i.grabPos, screenPos, pixelZ, uvDepth, sceneZ, bubbleCol);

					// Reflection
					half3 refl = reflect(-view, n_pixel);
					half3 skyColor = texCUBE(_Skybox, refl);
					#if _COMPUTEDIRECTIONALLIGHT_ON
					skyColor += pow(max(0., dot(refl, lightDir)), _DirectionalLightFallOff) * _DirectionalLightBoost * _LightColor0;
					#endif

					// Fresnel
					const float IOR_AIR = 1.0;
					const float IOR_WATER = 1.33;
					// reflectance at facing angle
					float R_0 = (IOR_AIR - IOR_WATER) / (IOR_AIR + IOR_WATER); R_0 *= R_0;
					// schlick's approximation
					float R_theta = R_0 + (1.0 - R_0) * pow(1.0 - max(dot(n_pixel, view), 0.), _FresnelPower);
					col = lerp(col, skyColor, R_theta);

					// Override final result with white foam - bubbles on surface
					#if _FOAM_ON
					col = lerp(col, whiteFoamCol.rgb, whiteFoamCol.a);
					#endif

					// Fog
					UNITY_APPLY_FOG(i.fogCoord, col);
	
					#if _DEBUGVISUALISESHAPESAMPLE_ON
					col = mix(col.rgb, i.debugtint, 0.5);
					#endif

					//col = (half3)i.foam_lodAlpha_worldXZUndisplaced.x;

					return col;
				}

				ENDCG
			}
		}
	}
}
