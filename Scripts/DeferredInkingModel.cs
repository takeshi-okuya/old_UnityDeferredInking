﻿using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace WCGL
{
    [ExecuteInEditMode]
    public class DeferredInkingModel : MonoBehaviour
    {
        [System.Serializable]
        public class Mesh
        {
            public Renderer mesh;
            public Material material;
            [Range(0, 255)] public int meshID;

            public void render(CommandBuffer commandBuffer, DeferredInkingCamera.RenderPhase phase, int modelID)
            {
                var renderer = mesh;
                if (renderer == null || renderer.isVisible == false || material == null) return;

                if (phase == DeferredInkingCamera.RenderPhase.GBuffer || material.shader == DeferredInkingLineShader)
                {
                    var id = new Vector2(modelID, meshID);
                    commandBuffer.SetGlobalVector("_ID", id);
                }

                if (phase == DeferredInkingCamera.RenderPhase.Line)
                {
                    if (material == null) return;
                    commandBuffer.DrawRenderer(renderer, material);
                }
                else
                {
                    commandBuffer.DrawRenderer(renderer, GBufferMaterial);
                }
            }
        }

        static List<DeferredInkingModel> Instances = new List<DeferredInkingModel>();
        static Material GBufferMaterial;
        static Shader DeferredInkingLineShader;

        [Range(1, 255)] public int modelID = 255;
        public List<Mesh> meshes = new List<Mesh>();

        void OnEnable()
        {
            Instances.Add(this);

            if (GBufferMaterial == null)
            {
                var shader = Shader.Find("Hidden/DeferredInking/GBuffer");
                GBufferMaterial = new Material(shader);

                DeferredInkingLineShader = Shader.Find("DeferredInking/Line");
            }
        }

        void OnDisable()
        {
            Instances.Remove(this);
        }

        public static void RenderActiveInstances(CommandBuffer commandBuffer, DeferredInkingCamera.RenderPhase phase)
        {
            foreach (var model in Instances)
            {
                foreach (var mesh in model.meshes)
                {
                    mesh.render(commandBuffer, phase, model.modelID);
                }
            }
        }
    }
}
