struct NeighborLoop { int startIdx, count; };

StructuredBuffer<NeighborLoop> NeighborLoops;
StructuredBuffer<int3> NeighborIdxs;
StructuredBuffer<float3> Vertices;

float _CurvatureThreshold;
float _CurvatureMaxWidth;

float compCurvature(float3 pos0, NeighborLoop neighborLoop)
{
	float A = 0;
	float3 sum = float3(0, 0, 0);

	for (int i = 0; i<neighborLoop.count; i++)
	{
		int idx = neighborLoop.startIdx + i;
		int3 neighborIdx = NeighborIdxs[idx];
		float3 pos1 = Vertices[neighborIdx.x];

		float3 pos2 = Vertices[neighborIdx.y];
		float3 dir20 = normalize(pos0 - pos2);
		float3 dir21 = normalize(pos1 - pos2);
		float cosa = dot(dir20, dir21);
		float cota = 1 / tan(acos(cosa));

		float3 pos3 = Vertices[neighborIdx.z];
		float3 dir30 = normalize(pos0 - pos3);
		float3 dir31 = normalize(pos1 - pos3);
		float cosb = dot(dir30, dir31);
		float cotb = 1 / tan(acos(cosb));

		float3 vec01 = pos1 - pos0;
		sum += (cota + cotb) * vec01;
		A += (cota + cotb) * dot(vec01, vec01);
	}

	return length(sum * 2 / A);
}

float compLineWidth(float curvature, float s, float t)
{
	return clamp(curvature, 0, s) / s * t + 1;
}

float compCurvatureWidth(uint id)
{
	float curvature = compCurvature(Vertices[id], NeighborLoops[id]);
	return compLineWidth(curvature, _CurvatureThreshold, _CurvatureMaxWidth);
}
