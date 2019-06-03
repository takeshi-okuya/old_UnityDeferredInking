using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace WCGL
{
    [ExecuteInEditMode]
    public class DeferredInkingModel : MonoBehaviour
    {
        public static List<DeferredInkingModel> Instances = new List<DeferredInkingModel>();

        public Material material;
        public List<Renderer> meshes = new List<Renderer>();

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
