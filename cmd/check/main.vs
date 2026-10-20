// anim: bone matrices through a hierarchy, clips sampled between and
// around their keys, looping, weights, and layers that touch only their
// own bones.
package main

import (
    "anim"
    "math"
    "math/geom"
)

var failures = 0

func check(_ ok: bool, _ what: string) {
    print(ok ? "ok    \(what)" : "FAIL  \(what)")
    if !ok { failures += 1 }
}

func near(_ a: geom.Vec3, _ b: geom.Vec3) -> bool {
    return math.Abs(a.X - b.X) < 1e-4 && math.Abs(a.Y - b.Y) < 1e-4 && math.Abs(a.Z - b.Z) < 1e-4
}

let half = float32(math.Pi) / 2

func main() -> int32 {
    // A body with an arm hanging from a shoulder at (0.3, 1.4, 0).
    let s = anim.Skeleton([anim.Bone("root"),
                           anim.Bone("body", parent: 0, pivot: geom.Vec3(0, 0.7, 0)),
                           anim.Bone("arm", parent: 1, pivot: geom.Vec3(0.3, 0.7, 0))])
    let arm = s.Index(of: "arm")!
    var pose = anim.Pose(rest: s.Count)
    let hand = geom.Vec3(0, -0.6, 0)   // the hand, in the arm's space
    check(near(s.Matrices(pose)[arm].TransformPoint(hand), geom.Vec3(0.3, 0.8, 0)), "at rest the hand hangs below the shoulder")

    pose.Rotations[arm] = anim.Euler(half, 0, 0)
    check(near(s.Matrices(pose)[arm].TransformPoint(hand), geom.Vec3(0.3, 1.4, -0.6)), "turning the arm +90° about X swings the hand forward (-Z)")

    pose.Rotations[0] = anim.Euler(0, half, 0)
    check(near(s.Matrices(pose)[arm].TransformPoint(hand), geom.Vec3(-0.6, 1.4, -0.3)), "turning the root turns everything under it")

    // A swing: 0 at 0 s, 90° at 0.5 s, back to 0 at 1 s.
    let swing = anim.Clip("swing", duration: 1, looping: false, tracks: [
        anim.Track(bone: arm, keys: [anim.Key(0, geom.Quat.Identity), anim.Key(0.5, anim.Euler(half, 0, 0)),
                                     anim.Key(1, geom.Quat.Identity)])])
    var p = anim.Pose(rest: s.Count)
    swing.Sample(0.25, into: &p)
    check(near(p.Rotations[arm].Rotate(geom.Vec3(0, -1, 0)), geom.Vec3(0, -math.Sqrt(0.5), -math.Sqrt(0.5))),
          "halfway between keys is halfway round")
    swing.Sample(2, into: &p)
    check(p.Rotations[arm] == geom.Quat.Identity, "a clip that doesn't loop holds its last key")

    var loop = swing
    loop.Looping = true
    loop.Sample(1.5, into: &p)
    check(near(p.Rotations[arm].Rotate(geom.Vec3(0, -1, 0)), geom.Vec3(0, 0, -1)), "a looping clip wraps its time")

    var w = anim.Pose(rest: s.Count)
    swing.Sample(0.5, into: &w, weight: 0.5)
    check(near(w.Rotations[arm].Rotate(geom.Vec3(0, -1, 0)), geom.Vec3(0, -math.Sqrt(0.5), -math.Sqrt(0.5))),
          "at weight 0.5 a clip goes half way from the pose")

    // Layers: a walk moves the body; a swing over it moves only the arm.
    let body = s.Index(of: "body")!
    let walk = anim.Clip("walk", duration: 1, looping: true, tracks: [
        anim.Track(bone: body, keys: [anim.Key(0, geom.Quat.Identity, offset: geom.Vec3(0, 0.05, 0)), anim.Key(0.5, geom.Quat.Identity)]),
        anim.Track(bone: arm, keys: [anim.Key(0, anim.Euler(0.3, 0, 0))])])
    var layered = anim.Pose(rest: s.Count)
    var l1 = anim.Layer(walk)
    var l2 = anim.Layer(swing)
    l1.Advance(0.25)
    l2.Advance(0.5)
    l1.Apply(&layered)
    l2.Apply(&layered)
    check(near(layered.Offsets[body], geom.Vec3(0, 0.025, 0)) &&
          near(layered.Rotations[arm].Rotate(geom.Vec3(0, -1, 0)), geom.Vec3(0, 0, -1)),
          "the swing layer takes the arm; the walk keeps the body")
    l2.Advance(1)
    check(l2.Finished && !l1.Finished, "a one-shot layer finishes, a looping one doesn't")

    let mid = anim.Blend(anim.Pose(rest: s.Count), layered, 0.5)
    check(near(mid.Offsets[body], geom.Vec3(0, 0.0125, 0)), "Blend mixes two poses")

    // Skeletons from model space, and poses back from model rotations.
    let m = anim.Skeleton(["hips", "spine", "thigh"], parents: [-1, 0, 0],
                          at: [geom.Vec3(0, 1, 0), geom.Vec3(0, 1.2, 0), geom.Vec3(0.1, 0.95, 0)])
    check(near(m.Bones[2].Pivot, geom.Vec3(0.1, -0.05, 0)) && near(m.RestPositions()[2], geom.Vec3(0.1, 0.95, 0)),
          "a skeleton from model-space joints keeps them where they were")
    var mp = anim.Pose(rest: m.Count)
    mp.Rotations[0] = anim.Euler(0, 0.6, 0)
    mp.Rotations[2] = anim.Euler(-0.9, 0, 0.2)
    mp.Offsets[0] = geom.Vec3(0.5, 0, 2)
    let placed = m.Transforms(mp)
    check(near(placed[2].Point(geom.Vec3(0, -0.4, 0)), m.Matrices(mp)[2].TransformPoint(geom.Vec3(0, -0.4, 0))),
          "Transforms agrees with Matrices")
    let back = m.PoseFrom(rotations: placed.map { $0.Rotation }, roots: [placed[0].Position])
    let again = m.Transforms(back)
    check(near(again[2].Point(geom.Vec3(0, -0.4, 0)), placed[2].Point(geom.Vec3(0, -0.4, 0))) && near(again[1].Position, placed[1].Position),
          "PoseFrom rebuilds a pose from model-space rotations and the root's place")

    layers()
    print(failures == 0 ? "all passed" : "\(failures) failed")
    return failures == 0 ? 0 : 1
}

// layers: masks keep a blend to some bones; events fire once as time passes them.
func layers() {
    // hips → spine → arm; hips → leg.
    let s = anim.Skeleton(["hips", "spine", "arm", "leg"], parents: [-1, 0, 1, 0],
                          at: [geom.Vec3(0, 1, 0), geom.Vec3(0, 1.3, 0), geom.Vec3(0.3, 1.5, 0), geom.Vec3(0.1, 0.9, 0)])
    var mask = anim.Mask(count: s.Count)
    mask.Set(s, from: 1, 1)
    mask.Weights[1] = 0.5
    check(mask.Weights == [0, 0.5, 1, 0], "a mask set from the spine covers it and what hangs from it, not the legs (\(mask.Weights))")
    let rest = anim.Pose(rest: s.Count)
    var turned = rest
    for i in 0..<s.Count { turned.Rotations[i] = geom.AxisAngle(geom.Vec3.UnitX, 1) }
    let b = anim.Blend(rest, turned, 1, mask: mask)
    func angle(_ q: geom.Quat) -> float32 { return 2 * math.Acos(math.Clamp(abs(q.W), 0, 1)) }
    check(abs(angle(b.Rotations[0])) < 1e-4 && abs(angle(b.Rotations[3])) < 1e-4 && abs(angle(b.Rotations[1]) - 0.5) < 1e-3 && abs(angle(b.Rotations[2]) - 1) < 1e-3,
          "a masked blend moves the arm all the way, the spine half, the hips and leg not at all")

    var once = anim.Clip("cast", duration: 1, looping: false, tracks: [])
    once.Events = [anim.Event("release", at: 0.4)]
    check(once.Crossed(from: 0, to: 0.39) == [] && once.Crossed(from: 0.39, to: 0.41) == ["release"] && once.Crossed(from: 0.4, to: 0.6) == [],
          "an event fires in the frame that passes it, once")
    var loop = anim.Clip("walk", duration: 1, looping: true, tracks: [])
    loop.Events = [anim.Event("step", at: 0.25), anim.Event("step", at: 0.75)]
    check(loop.Crossed(from: 0.5, to: 2.3).count == 4, "a looping clip's events fire every lap")
}
