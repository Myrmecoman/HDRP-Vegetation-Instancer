using UnityEngine;
using Unity.Collections;
using Unity.Jobs;
using Unity.Mathematics;
using System;
using System.Collections.Generic;
using System.Linq;
using Unity.Entities.UniversalDelegates;


// https://github.com/MangoButtermilch/Unity-Grass-Instancer/blob/main/GrassInstancerIndirect.cs
// https://github.com/GarrettGunnell/Grass


// /!\ ATTENTION : will only work with square and unrotated terrains. You should also not have holes in your terrain.
// So far this only works with 1 terrain using Terrain.activeTerrain to find it, but it should not be complicated to handle multiple terrains.
[ExecuteInEditMode]
public class GrassInstancer : MonoBehaviour
{
    public static GrassInstancer instance;

    [Header("Visuals")]
    [Tooltip("Run vegetation instancer in editor. This makes memory leaks so use carrefuly.")]
    public bool runInEditor = false;

    [Header("Procedural parameters")]
    [Tooltip("Random rotation")]
    public bool randomRotation = true;
    [Tooltip("Random displacement")]
    [Range(0, 1)]
    public float maxDisplacement = 0.5f;
    [Tooltip("Random size difference, 5 means it can go from size/5 to size*5")]
    [Range(1, 5)]
    public float randomSize = 0.5f;
    [Tooltip("Maximum slope to spawn plants on")]
    [Range(0, 1)]
    public float maxSlope = 0.5f;
    [Tooltip("Maximum texture value until no object is spawned")]
    [Range(0, 1)]
    public float falloff = 1f;

    [Header("Objects to spawn")]
    public GameObject plant;
    //public GameObject plantLOD;
    [Tooltip("The texture index to spawn the corresponding plant on. Set -1 to spawn everywhere.")]
    public int[] textureIndexes;

    [Header("Settings")]
    [Tooltip("Camera")]
    public Camera cam;
    [Tooltip("Light")]
    public Transform lightP;
    [Tooltip("The X and Z size of the chunks. Y is determined as chunkSize * 4")]
    public int chunkSize = 20;
    [Tooltip("Maximum display range")]
    public int viewDistance = 50;
    [Tooltip("Distance from which low quality plants are spawned instead of normal plants")]
    private int viewDistanceLOD = 30;
    [Tooltip("Number of plants in a chunk length. 5 means 5*5 plants per chunk")]
    [Range(1, 300)]
    public int plantDistanceInt = 5;


    private Terrain terrain;
    private FrustrumPlanes frustrumPlanes;
    private TerrainHeight terrainCpy;
    private TerrainTextures terrainTex;
    private int totalChunkPlantsCount;

    public ComputeBuffer heightBuffer;
    public ComputeBuffer texBuffer;

    private Mesh mesh;
    //private Mesh meshLOD;
    private Material mat;

    private uint[] args;

    // for both containers, int4 is real world position and 1 if LOD else 0
    // this contains all the chunks data
    private Dictionary<int4, GrassChunk> chunksData;


    private void UpdateAllVariables()
    {
        FreeContainers();

        // get terrain data
        terrain = Terrain.activeTerrain;
        frustrumPlanes = new FrustrumPlanes();
        chunksData = new Dictionary<int4, GrassChunk>(1024);
        terrainCpy = new TerrainHeight(terrain, Allocator.Persistent);
        terrainTex = new TerrainTextures(terrain, Allocator.Persistent);

        mesh = plant.GetComponent<MeshFilter>().sharedMesh;
        //meshLOD = plantLOD.GetComponent<MeshFilter>().sharedMesh;
        mat = plant.GetComponent<MeshRenderer>().sharedMaterial;

        if (chunkSize < 2)
            chunkSize = 2;
        if (viewDistanceLOD <= 0)
            viewDistanceLOD = 1;
        if (viewDistanceLOD > 500)
            viewDistanceLOD = 500;
        if (viewDistance <= 0)
            viewDistance = 2;
        if (viewDistance > 500)
            viewDistance = 500;

        totalChunkPlantsCount = plantDistanceInt * plantDistanceInt;

        args = new uint[5];
        args[0] = (uint)mesh.GetIndexCount(0);
        args[1] = (uint)totalChunkPlantsCount;
        args[2] = (uint)mesh.GetIndexStart(0);
        args[3] = (uint)mesh.GetBaseVertex(0);
        args[4] = 0;

        mat.SetFloat("randomSeed", 873.304f);
        mat.SetFloat("D1Size", plantDistanceInt);
        mat.SetFloat("chunkSize", chunkSize);
        mat.SetFloat("plantDistance", plantDistanceInt);
        mat.SetFloat("maxSlope", maxSlope);
        mat.SetFloat("sizeChange", randomSize);
        mat.SetInt("rotate", randomRotation ? 1 : 0);
        mat.SetFloat("displacement", maxDisplacement);
        mat.SetInt("textureIndex", textureIndexes[0]); // for now only support first texture
        mat.SetFloat("falloff", falloff);

        heightBuffer = new ComputeBuffer(terrainCpy.heightMap.Length, sizeof(float));
        heightBuffer.SetData(terrainCpy.heightMap.ToArray());
        mat.SetBuffer("heightMap", heightBuffer);
        mat.SetInteger("resolution", terrainCpy.resolution);
        mat.SetVector("sampleSize", new Vector4(terrainCpy.sampleSize.x, terrainCpy.sampleSize.y, 0, 0));
        mat.SetVector("AABBMin", new Vector4(terrainCpy.AABB.Min.x, terrainCpy.AABB.Min.y, terrainCpy.AABB.Min.z, 0));
        mat.SetVector("AABBMax", new Vector4(terrainCpy.AABB.Max.x, terrainCpy.AABB.Max.y, terrainCpy.AABB.Max.z, 0));

        texBuffer = new ComputeBuffer(terrainTex.textureMapAllTextures.Length, sizeof(float));
        texBuffer.SetData(terrainTex.textureMapAllTextures.ToArray());
        mat.SetBuffer("textureMapAllTextures", texBuffer);
        mat.SetInteger("terrainPosX", terrainTex.terrainPos.x);
        mat.SetInteger("terrainPosY", terrainTex.terrainPos.y);
        mat.SetFloat("terrainSizeX", terrainTex.terrainSize.x);
        mat.SetFloat("terrainSizeY", terrainTex.terrainSize.y);
        mat.SetInteger("textureArraySizeX", terrainTex.textureArraySize.x);
        mat.SetInteger("textureArraySizeY", terrainTex.textureArraySize.y);
        mat.SetInteger("resolutionTex", terrainTex.resolution);
        mat.SetInteger("textureCount", terrainTex.textureCount);

        terrainTex.Dispose();
    }


    private void Awake()
    {
        // make this a singleton
        if (instance == null)
            instance = this;
        else
        {
            Destroy(gameObject);
            return;
        }

        UpdateAllVariables(); // this is done in a separate function so that it can be called when RunInEditor changes
    }


    private void OnDestroy()
    {
        FreeContainers();
    }


    private void FreeContainers()
    {
        if (chunksData != null)
            chunksData.Clear();

        if (terrainCpy.heightMap.IsCreated)
            terrainCpy.Dispose();
        if (terrainTex.textureMap.IsCreated)
            terrainTex.Dispose();

        heightBuffer?.Release();
        texBuffer?.Release();
    }


    private void DisposeChunk(GrassChunk g)
    {
        g.argsBuffer?.Release();
    }


    private GrassChunk InitializeChunk(int4 center)
    {
        var chunk = new GrassChunk();

        chunk.argsBuffer = new ComputeBuffer(1, 5 * sizeof(uint), ComputeBufferType.IndirectArguments);
        chunk.argsBuffer.SetData(args);

        chunk.material = new Material(mat);

        Vector3 lightDir = lightP.forward;
        chunk.material.SetFloat("ViewRangeSq", (viewDistance - chunkSize/2) * (viewDistance - chunkSize / 2));
        chunk.material.SetVector("CamPos", new Vector4(cam.transform.position.x, cam.transform.position.y, cam.transform.position.z, 1));
        chunk.material.SetVector("LightDir", new Vector4(lightDir.x, lightDir.y, lightDir.z, 1));

        return chunk;
    }


    // once this function is done, the chunks variable only contains the visible chunks, with info wether they are LOD or not
    private void UpdateChunks()
    {
        // find the chunks which appared on screen, and those which disappeared
        var chunksSampler = new PickVisibleChunksJob
        {
            terrainData = terrainCpy,
            newChunks = new NativeList<int4>(Allocator.TempJob),
            deletedChunks = new NativeList<int4>(Allocator.TempJob),
            modifiedChunks = new NativeList<int4>(Allocator.TempJob),
            existingChunks = new NativeArray<int4>(chunksData.Keys.ToArray(), Allocator.TempJob),
            frustrumPlanes = frustrumPlanes,
            size1D = (int)terrain.terrainData.size.x,
            camPos = new int3((int)cam.transform.position.x, (int)cam.transform.position.y, (int)cam.transform.position.z),
            terrainPos = new int3((int)terrain.transform.position.x, (int)terrain.transform.position.y, (int)terrain.transform.position.z),
            chunkSize = chunkSize,
            viewDistanceLODSq = viewDistanceLOD * viewDistanceLOD,
            viewDistanceSq = viewDistance * viewDistance,
        };
        chunksSampler.Schedule().Complete();

        // add the chunks which appeared on view
        for (int i = 0; i < chunksSampler.newChunks.Length; i++)
        {
            chunksData.Add(chunksSampler.newChunks[i], InitializeChunk(chunksSampler.newChunks[i]));
        }

        // remove the chunks which disappeared from view
        for (int i = 0; i < chunksSampler.deletedChunks.Length; i++)
        {
            DisposeChunk(chunksData[chunksSampler.deletedChunks[i]]);
            chunksData.Remove(chunksSampler.deletedChunks[i]);
        }

        // change the state of chunks which turned from non-LOD to LOD and vice versa
        for (int i = 0; i < chunksSampler.modifiedChunks.Length; i++)
        {
            var savedData = chunksData[chunksSampler.modifiedChunks[i]];
            chunksData.Remove(chunksSampler.modifiedChunks[i]);
            chunksData.Add(
                new int4(chunksSampler.modifiedChunks[i].x,
                chunksSampler.modifiedChunks[i].y,
                chunksSampler.modifiedChunks[i].z,
                math.abs(chunksSampler.modifiedChunks[i].w - 1)),
                savedData);
        }

        chunksSampler.deletedChunks.Dispose();
        chunksSampler.modifiedChunks.Dispose();
        chunksSampler.existingChunks.Dispose();
        chunksSampler.newChunks.Dispose();
    }


    private void Update()
    {
        if (!Application.isPlaying && !runInEditor)
            return;
        if (!Application.isPlaying)
        {
            if (runInEditor && chunksData == null)
                Awake();
            if (runInEditor)
                UpdateAllVariables();
        }

        double t = Time.realtimeSinceStartupAsDouble;

        var planes = GeometryUtility.CalculateFrustumPlanes(cam);
        frustrumPlanes.p1 = planes[0];
        frustrumPlanes.p2 = planes[1];
        frustrumPlanes.p3 = planes[2];
        frustrumPlanes.p4 = planes[3];
        frustrumPlanes.p5 = planes[4];
        frustrumPlanes.p6 = planes[5];

        UpdateChunks();

        // draw objects
        var bounds = new Bounds(cam.transform.position, Vector3.one * cam.farClipPlane);
        foreach (var e in chunksData)
        {
            GrassChunk g = e.Value;
            g.material.SetVector("CamPos", new Vector4(cam.transform.position.x, cam.transform.position.y, cam.transform.position.z, 1));
            g.material.SetInteger("chunkPosX", e.Key.x);
            g.material.SetInteger("chunkPosZ", e.Key.z);
            Graphics.DrawMeshInstancedIndirect(mesh, 0, g.material, bounds, g.argsBuffer, 0, null, UnityEngine.Rendering.ShadowCastingMode.Off);
        }
        
        double chunkDrawing = Time.realtimeSinceStartupAsDouble - t;
        //Debug.Log("Full loop time : " + chunkDrawing + ", total objects spawned : " + totalChunkPlantsCount * chunksData.Count);
    }


    private void OnDrawGizmos()
    {
        if ((!Application.isPlaying && !runInEditor) || chunksData == null)
            return;

        foreach (var e in chunksData)
        {
            if (e.Key.w == 0)
                Gizmos.color = Color.red;
            else
                Gizmos.color = Color.yellow;

            Gizmos.DrawWireCube(new float3(e.Key.x, e.Key.y, e.Key.z), new float3(chunkSize, 1, chunkSize));
        }
    }
}


public struct GrassChunk
{
    public ComputeBuffer argsBuffer;
    public Material material;
}
