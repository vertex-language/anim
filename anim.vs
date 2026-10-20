// Package anim is skeletal animation: a skeleton of bones, a pose that
// turns and moves them, clips of keyframes sampled into poses, and
// blending, whole or per bone, so a walk and a swing of one arm play at
// once. It computes bone matrices; drawing what hangs on them (rigid
// parts or skinned meshes) is the renderer's.
//
// Conventions are math/geom's: right-handed, Y up, radians.
package anim

import (
    "math/geom"
)

/// Bone is one joint: where it sits in its parent's space when the
/// skeleton is at rest.
public struct Bone {
    public var Name: string
    /// The parent's index in the skeleton, or -1 for a root. A parent
    /// comes before its children.
    public var Parent: int
    /// The joint's place in the parent's space, at rest.
    public var Pivot: geom.Vec3

    public init(_ name: string, parent: int = -1, pivot: geom.Vec3 = geom.Vec3.Zero) {
        Name = name
        Parent = parent
        Pivot = pivot
    }
}

/// Skeleton is bones in order, parents first.
public struct Skeleton {
    public var Bones: [Bone]

    public init(_ bones: [Bone]) {
        Bones = bones
    }

    public var Count: int { return Bones.count }

    /// Index is the bone with this name, if there is one.
    public func Index(of name: string) -> int? {
        return Bones.firstIndex(where: { $0.Name == name })
    }
}

/// Pose turns and moves each bone from rest: Rotations[i] about bone i's
/// pivot, then Offsets[i] added to the pivot.
public struct Pose {
    public var Rotations: [geom.Quat]
    public var Offsets: [geom.Vec3]

    /// Rest is every bone at rest.
    public init(rest count: int) {
        Rotations = [geom.Quat](repeating: geom.Quat.Identity, count: count)
        Offsets = [geom.Vec3](repeating: geom.Vec3.Zero, count: count)
    }
}

extension Skeleton {
    /// Matrices is each bone's transform from its own space to the
    /// skeleton's, for a pose: what to draw a part hanging on that bone with.
    public func Matrices(_ pose: Pose) -> [geom.Mat4] {
        var out: [geom.Mat4] = []
        out.reserveCapacity(Bones.count)
        for (i, b) in Bones.enumerated() {
            let local = geom.Translation(b.Pivot + pose.Offsets[i]) * pose.Rotations[i].Matrix()
            out.append(b.Parent >= 0 ? out[b.Parent] * local : local)
        }
        return out
    }
}

/// Euler is a rotation by x about X, then y about Y, then z about Z.
public func Euler(_ x: float32, _ y: float32, _ z: float32) -> geom.Quat {
    return geom.AxisAngle(geom.Vec3.UnitZ, z) * geom.AxisAngle(geom.Vec3.UnitY, y) * geom.AxisAngle(geom.Vec3.UnitX, x)
}

// ---- clips ----

/// Key is a bone's rotation and offset at a time.
public struct Key {
    public var Time: float32
    public var Rotation: geom.Quat
    public var Offset: geom.Vec3

    public init(_ time: float32, _ rotation: geom.Quat, offset: geom.Vec3 = geom.Vec3.Zero) {
        Time = time
        Rotation = rotation
        Offset = offset
    }
}

/// Track is one bone's keys, in time order.
public struct Track {
    public var Bone: int
    public var Keys: [Key]

    public init(bone: int, keys: [Key]) {
        Bone = bone
        Keys = keys
    }
}

/// Clip is an animation: tracks for some bones over Duration seconds.
/// Bones without a track aren't touched when it's sampled.
public struct Clip {
    public var Name: string
    public var Duration: float32
    public var Looping: bool
    public var Tracks: [Track]
    /// Named moments in it (see Crossed).
    public var Events: [Event] = []

    public init(_ name: string, duration: float32, looping: bool, tracks: [Track]) {
        Name = name
        Duration = duration
        Looping = looping
        Tracks = tracks
    }
}

extension Clip {
    /// Sample writes the clip at time t into the pose, `weight` of the way
    /// from what the pose holds (1 replaces it). A looping clip wraps t; a
    /// clip that doesn't holds its first and last keys.
    public func Sample(_ t: float32, into pose: inout Pose, weight: float32 = 1) {
        if weight <= 0 { return }
        var time = t
        if Looping && Duration > 0 {
            time = time - Duration * (time / Duration).rounded(.down)
        }
        for track in Tracks {
            let (r, o) = sample(track.Keys, time)
            let i = track.Bone
            if weight >= 1 {
                pose.Rotations[i] = r
                pose.Offsets[i] = o
            } else {
                pose.Rotations[i] = geom.Slerp(pose.Rotations[i], r, weight)
                pose.Offsets[i] = geom.Lerp(pose.Offsets[i], o, weight)
            }
        }
    }

    func sample(_ keys: [Key], _ t: float32) -> (geom.Quat, geom.Vec3) {
        guard let first = keys.first, let last = keys.last else { return (geom.Quat.Identity, geom.Vec3.Zero) }
        if t <= first.Time { return (first.Rotation, first.Offset) }
        if t >= last.Time {
            // A looping clip runs from its last key back round to its first.
            if Looping && Duration > last.Time {
                let f = (t - last.Time) / (Duration - last.Time + first.Time)
                return (geom.Slerp(last.Rotation, first.Rotation, f), geom.Lerp(last.Offset, first.Offset, f))
            }
            return (last.Rotation, last.Offset)
        }
        var k = 1
        while keys[k].Time < t { k += 1 }
        let a = keys[k - 1], b = keys[k]
        let f = (t - a.Time) / (b.Time - a.Time)
        return (geom.Slerp(a.Rotation, b.Rotation, f), geom.Lerp(a.Offset, b.Offset, f))
    }
}

/// Event is a named moment in a clip: where a foot lands, where a sword
/// connects, where a spell leaves the hand.
public struct Event {
    public var Name: string
    public var Time: float32

    public init(_ name: string, at time: float32) {
        Name = name
        Time = time
    }
}

extension Clip {
    /// Crossed is the events passed going from t0 to t1 (after t0, up to
    /// and including t1), in order; a looping clip counts each lap.
    public func Crossed(from t0: float32, to t1: float32) -> [string] {
        var out: [string] = []
        if t1 <= t0 || Events.isEmpty { return out }
        if !Looping || Duration <= 0 {
            for e in Events where e.Time > t0 && e.Time <= t1 { out.append(e.Name) }
            return out
        }
        var lap = (t0 / Duration).rounded(.down)
        while lap * Duration < t1 {
            for e in Events {
                let at = lap * Duration + e.Time
                if at > t0 && at <= t1 { out.append(e.Name) }
            }
            lap += 1
        }
        return out
    }
}

/// Mask is how much each bone of a skeleton takes from a blend, 0…1:
/// an upper-body action leaves the legs to the walk.
public struct Mask {
    public var Weights: [float32]

    /// All bones at `weight`.
    public init(count: int, weight: float32 = 0) {
        Weights = [float32](repeating: weight, count: count)
    }

    /// From bones up the skeleton, each and everything below it, at a weight.
    public mutating func Set(_ s: Skeleton, from bone: int, _ weight: float32) {
        Weights[bone] = weight
        for (i, b) in s.Bones.enumerated() where i > bone && descends(s, i, from: bone) { Weights[i] = weight }
    }

    func descends(_ s: Skeleton, _ i: int, from bone: int) -> bool {
        var p = s.Bones[i].Parent
        while p >= 0 {
            if p == bone { return true }
            p = s.Bones[p].Parent
        }
        return false
    }
}

/// Blend is a pose `weight` of the way from a to b, each bone as far as
/// the mask lets it.
public func Blend(_ a: Pose, _ b: Pose, _ weight: float32, mask: Mask) -> Pose {
    var out = a
    for i in 0..<a.Rotations.count {
        let w = weight * (i < mask.Weights.count ? mask.Weights[i] : 0)
        if w <= 0 { continue }
        out.Rotations[i] = geom.Slerp(a.Rotations[i], b.Rotations[i], w)
        out.Offsets[i] = geom.Lerp(a.Offsets[i], b.Offsets[i], w)
    }
    return out
}

/// Blend is a pose `weight` of the way from a to b, every bone.
public func Blend(_ a: Pose, _ b: Pose, _ weight: float32) -> Pose {
    var out = a
    for i in 0..<a.Rotations.count {
        out.Rotations[i] = geom.Slerp(a.Rotations[i], b.Rotations[i], weight)
        out.Offsets[i] = geom.Lerp(a.Offsets[i], b.Offsets[i], weight)
    }
    return out
}

/// Layer is a clip playing: where it is, how fast it goes, how much of it
/// shows.
public struct Layer {
    public var Clip: Clip
    public var Time: float32 = 0
    public var Speed: float32 = 1
    public var Weight: float32 = 1

    public init(_ clip: Clip) {
        self.Clip = clip
    }

    /// Advance moves the playhead on by dt seconds at Speed.
    public mutating func Advance(_ dt: float32) {
        Time += dt * Speed
    }

    /// Finished is whether a clip that doesn't loop has played through.
    public var Finished: bool { return !Clip.Looping && Time >= Clip.Duration }

    /// Apply samples the layer into the pose at its weight.
    public func Apply(_ pose: inout Pose) {
        Clip.Sample(Time, into: &pose, weight: Weight)
    }
}

// ---- skeletons from model space ----

extension Skeleton {
    /// A skeleton from joints placed in model space: names, each one's
    /// parent (parents first, -1 for a root) and where it sits at rest.
    /// Every bone's frame is the model's axes, so a rotation in a clip
    /// means the same thing on every bone (X pitches, Y turns, Z rolls),
    /// whatever frames the joints had where they came from.
    public init(_ names: [string], parents: [int], at positions: [geom.Vec3]) {
        var bones: [Bone] = []
        for i in 0..<names.count {
            let p = parents[i]
            bones.append(Bone(names[i], parent: p, pivot: p >= 0 ? positions[i] - positions[p] : positions[i]))
        }
        self.init(bones)
    }

    /// RestPositions is where each joint sits in model space at rest.
    public func RestPositions() -> [geom.Vec3] {
        var out: [geom.Vec3] = []
        out.reserveCapacity(Bones.count)
        for b in Bones {
            out.append(b.Parent >= 0 ? out[b.Parent] + b.Pivot : b.Pivot)
        }
        return out
    }

    /// Transforms is each bone's placement in model space for a pose: the
    /// same as Matrices, kept as positions and rotations.
    public func Transforms(_ pose: Pose) -> [geom.Transform] {
        var out: [geom.Transform] = []
        out.reserveCapacity(Bones.count)
        for (i, b) in Bones.enumerated() {
            let local = geom.Transform(position: b.Pivot + pose.Offsets[i], rotation: pose.Rotations[i])
            out.append(b.Parent >= 0 ? out[b.Parent] * local : local)
        }
        return out
    }

    /// PoseFrom is the pose that turns each bone to a rotation in model space,
    /// with the roots moved so their joints land on `roots` (model-space
    /// positions, one per root in bone order; roots left out stay put).
    /// It's how a pose comes back from a ragdoll or a solver that works in
    /// model space.
    public func PoseFrom(rotations: [geom.Quat], roots: [geom.Vec3] = []) -> Pose {
        var pose = Pose(rest: Bones.count)
        var root = 0
        for (i, b) in Bones.enumerated() {
            if b.Parent >= 0 {
                pose.Rotations[i] = (rotations[b.Parent].Conjugate() * rotations[i]).Normalized()
            } else {
                pose.Rotations[i] = rotations[i]
                if root < roots.count { pose.Offsets[i] = roots[root] - b.Pivot }
                root += 1
            }
        }
        return pose
    }
}
