using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace WCGL
{
    [ExecuteInEditMode]
    public class DeferredInkingModel : MonoBehaviour
    {
        [System.Serializable]
        public struct Mesh
        {
            public Renderer mesh;
            public uint meshID;
        }

        public static List<DeferredInkingModel> Instances = new List<DeferredInkingModel>();

        public Material material;
        public List<Mesh> meshes = new List<Mesh>();

        void Start() { } //for Inspector ON_OFF

        void Awake()
        {
            Instances.Add(this);
        }

        void OnDestroy()
        {
            Instances.Remove(this);
        }

    }
}
