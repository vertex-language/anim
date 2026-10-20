# anim

[![package: vs-package](https://img.shields.io/badge/package-vs--package-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![license: MIT](https://img.shields.io/badge/license-MIT-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](LICENSE)

Skeletal animation: a skeleton of bones, a pose that turns and moves
them, clips of keyframes sampled into poses, and blending, whole or per
bone, so a walk and the swing of one arm play at once. It computes bone
matrices; drawing what hangs on them, rigid parts or skinned meshes, is
the renderer's. Pure Vertex, no `gpu`.

Conventions are `math/geom`'s: right-handed, Y up, radians.

---

## Package

| Name | What it is |
| :--- | :--- |
| `Bone`, `Skeleton` | Bones by name, each with a parent (parents first) and a pivot in its parent's space. `Index(of:)` finds one by name. |
| `Pose` | A rotation and an offset per bone. `Skeleton.Matrices(pose)` gives each bone's model-space matrix. |
| `Key`, `Track`, `Clip` | Keyframes of one bone; a named clip of tracks with a duration, looping or held on its last key. `Sample(t, into:, weight:)` writes only the bones the clip has tracks for, so a clip of just an arm layers over a walk. |
| `Layer` | A clip playing: `Time`, `Speed`, `Weight`, `Advance`, `Finished`, `Apply`. |
| `Blend`, `Euler` | One pose part of the way to another (slerped); a rotation from X, Y, Z angles. |
| `Mask`, `Blend(a, b, w, mask:)` | How much each bone takes from a blend (`Set` from a bone and all below it): an action on the upper body over a walk. |
| `Event`, `Clip.Events`, `Crossed(from:to:)` | Named moments in a clip (a foot lands, a spell leaves the hand), fired once as time passes them, every lap of a loop. |
| `Skeleton(_:parents:at:)` | A skeleton from joints placed in model space. Every bone gets the model's axes, so a clip's rotation means the same on every bone (X pitches, Y turns, Z rolls) whatever frames the joints had in the file they came from. `RestPositions()` gives them back. |
| `Transforms`, `PoseFrom` | Each bone's model-space placement for a pose (as `geom.Transform`s), and the reverse: the pose that turns bones to given model-space rotations with the root at a given place. How a ragdoll's or a solver's result comes back as a pose. |

### `anim/skin`

Linear blend skinning, four bones a vertex. `Skin` holds `Joints`,
`Weights` and `InverseBind`; `Palette(matrices)` is each bone's motion
from rest (upload it for GPU skinning), `Deform(mesh, palette)` does it on
the CPU, `Normalize()` makes each vertex's weights sum to 1, and
`InverseBind(skeleton)` builds the binds for a model-axes skeleton.
`Morph` is a morph target (blend shape), sparse: the vertices it moves
and how far, positions and normals; `Morphed(mesh, morphs, weights)`
applies them.

---

## Example

```vertex
import "anim"
import "math/geom"

let s = anim.Skeleton([anim.Bone("root"),
                       anim.Bone("arm", parent: 0, pivot: geom.Vec3(0.3, 1.4, 0))])
let chop = anim.Clip("chop", duration: 0.3, looping: true, tracks: [
    anim.Track(bone: 1, keys: [anim.Key(0, anim.Euler(0, 0, 0)),
                               anim.Key(0.1, anim.Euler(1.9, 0, 0)),
                               anim.Key(0.3, anim.Euler(0, 0, 0))]),
])
var swing = anim.Layer(chop)
var pose = anim.Pose(rest: s.Count)
swing.Advance(0.05)
swing.Apply(&pose)
let arm = s.Matrices(pose)[1]   // place the arm's mesh with this
```

---

## Testing

```bash
vsc run check    # bone hierarchies, sampling, looping and holding, layers, blending, model-space skeletons and poses, masks, events
```

---

## License

[MIT](LICENSE)
