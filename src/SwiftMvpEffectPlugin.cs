using System.Text.Json;
using Microsoft.Extensions.Logging;
using SwiftlyS2.Shared;
using SwiftlyS2.Shared.Commands;
using SwiftlyS2.Shared.EntitySystem;
using SwiftlyS2.Shared.Events;
using SwiftlyS2.Shared.GameEventDefinitions;
using SwiftlyS2.Shared.GameEvents;
using SwiftlyS2.Shared.Misc;
using SwiftlyS2.Shared.Natives;
using SwiftlyS2.Shared.Players;
using SwiftlyS2.Shared.Plugins;
using SwiftlyS2.Shared.SchemaDefinitions;

namespace SwiftMvpEffect;

[PluginMetadata(
    Id = "swift_mvp_effect",
    Version = "0.1.0",
    Name = "Swift MVP Effect",
    Author = "SkinTools",
    Description = "Plays a screen-locked animated particle banner when round_mvp fires.",
    MinimumAPIVersion = "1.1.0"
)]
public sealed class SwiftMvpEffectPlugin(ISwiftlyCore core) : BasePlugin(core)
{
    private const string ConfigFileName = "mvp_effect.json";
    private const float AnimationSeconds = 2.4f;
    private const float EntityStopGraceSeconds = 0.35f;

    private const string EffectParticle =
        "particles/swift_mvp_effect/mvp_overlay.vpcf";
    private const string AtlasEffectParticle =
        "particles/swift_mvp_effect/mvp_atlas_overlay.vpcf";

    private readonly Dictionary<int, MvpEffectSession> activeEffects = [];
    private readonly HashSet<CHandle<CParticleSystem>> pendingRemovals = [];
    private MvpEffectConfig config = MvpEffectConfig.Default;

    private ILogger<SwiftMvpEffectPlugin> Logger =>
        Core.LoggerFactory.CreateLogger<SwiftMvpEffectPlugin>();

    public override void Load(bool hotReload)
    {
        config = LoadConfiguration();
        Core.Event.OnPrecacheResource += OnPrecacheResource;
        Core.Event.OnClientConnected += OnClientConnected;
        Core.Event.OnClientDisconnected += OnClientDisconnected;

        Logger.LogInformation(
            "SwiftMvpEffect loaded: enabled={Enabled}, audience={Audience}, " +
            "scale={Scale:F2}, offsetY={OffsetY:F2}, " +
            "assets=transparent-emblem+optional-60f-atlas.",
            config.Enabled,
            config.Audience,
            config.Scale,
            config.OffsetY);
    }

    public override void Unload()
    {
        Core.Event.OnPrecacheResource -= OnPrecacheResource;
        Core.Event.OnClientConnected -= OnClientConnected;
        Core.Event.OnClientDisconnected -= OnClientDisconnected;
        CloseAllEffects("unload");
        FlushPendingRemovals("unload");
    }

    private void OnPrecacheResource(IOnPrecacheResourceEvent @event)
    {
        @event.AddItem(EffectParticle);
        @event.AddItem(AtlasEffectParticle);

        Logger.LogInformation(
            "SwiftMvpEffect precached the emblem and optional 60-frame atlas resources.");
    }

    private void OnClientDisconnected(IOnClientDisconnectedEvent @event)
    {
        CloseEffect(@event.PlayerId, "client-disconnected");
    }

    private void OnClientConnected(IOnClientConnectedEvent @event)
    {
        foreach (var session in activeEffects.Values)
        {
            var visible = session.Slot == @event.PlayerId;
            foreach (var handle in session.Particles)
            {
                if (handle.IsValid && handle.Value?.IsValidEntity == true)
                    handle.Value.SetTransmitState(visible, @event.PlayerId);
            }
        }
    }

    [GameEventHandler(HookMode.Post)]
    public HookResult OnRoundMvp(EventRoundMvp @event)
    {
        if (!config.Enabled)
            return HookResult.Continue;

        var mvpPlayer = @event.UserIdPlayer;
        var targetSlots = ResolveAudience(mvpPlayer)
            .Select(player => player.Slot)
            .Distinct()
            .ToArray();

        var spawned = 0;
        foreach (var slot in targetSlots)
        {
            if (TryPlayForSlot(slot, "round-mvp"))
                spawned++;
        }

        Logger.LogInformation(
            "MVP_EFFECT_TRIGGER mvpSlot={MvpSlot} reason={Reason} value={Value} " +
            "audience={Audience} targets={TargetCount} spawned={SpawnedCount}.",
            mvpPlayer?.Slot ?? -1,
            @event.Reason,
            @event.Value,
            config.Audience,
            targetSlots.Length,
            spawned);

        return HookResult.Continue;
    }

    [GameEventHandler(HookMode.Pre)]
    public HookResult OnRoundPrestart(EventRoundPrestart @event)
    {
        CloseAllEffects("round-prestart");
        return HookResult.Continue;
    }

    [Command(
        "swift_mvp_test",
        registerRaw: true,
        helpText: "Play the MVP animation for the command sender.")]
    public void TestMvpEffect(ICommandContext context)
    {
        var player = context.Sender;
        if (player?.IsValid != true)
        {
            context.Reply("[SwiftMVP] This command must be run by an in-game player.");
            return;
        }

        if (!TryPlayForSlot(player.Slot, "test-command"))
        {
            context.Reply("[SwiftMVP] Failed to create the MVP particle. Check the server log.");
            return;
        }

        context.Reply("[SwiftMVP] Playing the client-animated MVP flyover.");
    }

    [Command(
        "swift_mvp_test_atlas",
        registerRaw: true,
        helpText: "Play the preserved 60-frame sequence-atlas MVP banner.")]
    public void TestMvpAtlasEffect(ICommandContext context)
    {
        var player = context.Sender;
        if (player?.IsValid != true)
        {
            context.Reply("[SwiftMVP] This command must be run by an in-game player.");
            return;
        }

        if (!TryPlayForSlot(
                player.Slot,
                AtlasEffectParticle,
                "sequence-atlas-60f",
                "atlas-test-command"))
        {
            context.Reply(
                "[SwiftMVP] Failed to create the 60-frame MVP atlas particle. " +
                "Check the server log.");
            return;
        }

        context.Reply("[SwiftMVP] Playing the preserved 60-frame MVP atlas banner.");
    }

    private IEnumerable<IPlayer> ResolveAudience(IPlayer? mvpPlayer)
    {
        if (config.Audience.Equals("mvp", StringComparison.OrdinalIgnoreCase))
        {
            if (mvpPlayer?.IsValid == true)
                yield return mvpPlayer;
            yield break;
        }

        foreach (var player in Core.PlayerManager.GetAllPlayers())
        {
            if (player?.IsValid == true)
                yield return player;
        }
    }

    private bool TryPlayForSlot(int slot, string reason) =>
        TryPlayForSlot(slot, EffectParticle, "transparent-emblem", reason);

    private bool TryPlayForSlot(
        int slot,
        string effectName,
        string effectKind,
        string reason)
    {
        var owner = Core.PlayerManager.GetPlayer(slot);
        if (owner?.IsValid != true)
            return false;

        CloseEffect(slot, $"replace:{reason}");

        var handles = new List<CHandle<CParticleSystem>>(1);
        CParticleSystem? pendingParticle = null;
        try
        {
            pendingParticle = CreateConfiguredParticle(slot, effectName);
            handles.Add(Core.EntitySystem.GetRefEHandle(pendingParticle));
            pendingParticle = null;

            var session = new MvpEffectSession(slot, [.. handles]);
            activeEffects[slot] = session;
            StartAnimation(session, reason);
            ScheduleNaturalRemoval(session, reason);

            Logger.LogInformation(
                "MVP_EFFECT_SPAWN slot={Slot} entities={EntityIndexes} " +
                "effect={EffectKind} reason={Reason} " +
                "cp34=({Scale:F2},0,{OffsetY:F2}), " +
                "motion=client-collection-age-left-in-bounce-hold-right-out.",
                slot,
                string.Join(
                    ",",
                    handles
                        .Where(handle => handle.IsValid)
                        .Select(handle => (long?)handle.Value?.Index ?? -1L)),
                effectKind,
                reason,
                config.Scale,
                config.OffsetY);
            return true;
        }
        catch (Exception exception)
        {
            Logger.LogError(
                exception,
                "Failed to spawn MVP particle for slot {Slot}; " +
                "effect={EffectKind} reason={Reason}.",
                slot,
                effectKind,
                reason);
            DespawnImmediately(pendingParticle, $"spawn-error:{reason}");
            foreach (var handle in handles)
            {
                if (handle.IsValid)
                    DespawnImmediately(handle.Value, $"spawn-rollback:{reason}");
            }
            return false;
        }
    }

    private CParticleSystem CreateConfiguredParticle(
        int ownerSlot,
        string effectName)
    {
        using var keyValues = new CEntityKeyValues();
        keyValues.SetString("effect_name", effectName);
        keyValues.SetBool("start_active", false);
        keyValues.SetInt32("flag_as_weather", 0);
        keyValues.SetVector("origin", Vector.Zero);

        var particle = Core.EntitySystem.CreateEntityByDesignerName<CParticleSystem>(
            "info_particle_system")
            ?? throw new InvalidOperationException(
                "CreateEntityByDesignerName(info_particle_system) returned null.");

        try
        {
            particle.DispatchSpawn(keyValues);
            particle.NoSave = true;
            particle.NoFreeze = true;
            particle.NoRamp = true;
            particle.Active = false;
            particle.NoSaveUpdated();
            particle.NoFreezeUpdated();
            particle.NoRampUpdated();
            particle.ActiveUpdated();

            foreach (var player in Core.PlayerManager.GetAllPlayers())
            {
                if (player?.IsValid == true)
                    particle.SetTransmitState(
                        player.Slot == ownerSlot,
                        player.Slot);
            }

            // CP34 is configured once before Start. The VPCF's collection-age renderer
            // segments own position, scale bounce, hold, exit, and alpha locally on the
            // client, avoiding per-tick replication.
            // CP34.x = scale, CP34.z = vertical offset.
            particle.ServerControlPointAssignments[0] = 34;
            particle.ServerControlPoints[0] = new Vector(
                config.Scale,
                0f,
                config.OffsetY);
            particle.ServerControlPointAssignmentsUpdated();
            particle.ServerControlPointsUpdated();
            return particle;
        }
        catch
        {
            DespawnImmediately(particle, "animation-spawn-error");
            throw;
        }
    }

    private void StartAnimation(
        MvpEffectSession session,
        string reason)
    {
        if (!activeEffects.TryGetValue(session.Slot, out var current) ||
            !ReferenceEquals(current, session) ||
            session.Particles.Length != 1)
        {
            return;
        }

        var handle = session.Particles[0];
        if (!handle.IsValid || handle.Value?.IsValidEntity != true)
            return;

        var particle = handle.Value;
        particle.AcceptInput<string>("Start", null);
        particle.Active = true;
        particle.ActiveUpdated();

        Logger.LogDebug(
            "MVP_EFFECT_START slot={Slot} entity={EntityIndex} reason={Reason}.",
            session.Slot,
            particle.Index,
            reason);
    }

    private void ScheduleNaturalRemoval(
        MvpEffectSession session,
        string reason)
    {
        Core.Scheduler.DelayBySeconds(AnimationSeconds + 0.10f, () =>
        {
            if (!activeEffects.TryGetValue(session.Slot, out var current) ||
                !ReferenceEquals(current, session))
            {
                return;
            }

            activeEffects.Remove(session.Slot);
            BeginRemoval(session, $"animation-complete:{reason}");
        });
    }

    private void CloseEffect(int slot, string reason)
    {
        if (!activeEffects.Remove(slot, out var session))
            return;

        BeginRemoval(session, reason);
    }

    private void CloseAllEffects(string reason)
    {
        var effects = activeEffects.Values.ToArray();
        activeEffects.Clear();
        foreach (var session in effects)
            BeginRemoval(session, reason);
    }

    private void BeginRemoval(
        MvpEffectSession session,
        string reason)
    {
        foreach (var handle in session.Particles)
            BeginRemoval(handle, reason);
    }

    private void BeginRemoval(
        CHandle<CParticleSystem> handle,
        string reason)
    {
        if (!handle.IsValid)
            return;

        var particle = handle.Value;
        if (particle?.IsValidEntity != true)
            return;

        var entityIndex = particle.Index;
        pendingRemovals.Add(handle);

        try
        {
            particle.AcceptInput<string>("StopPlayEndCap", string.Empty);
            particle.Active = false;
            particle.ActiveUpdated();
        }
        catch (Exception exception)
        {
            Logger.LogDebug(
                exception,
                "MVP particle stop failed for entity {EntityIndex}; cleanup will continue.",
                entityIndex);
        }

        Core.Scheduler.DelayBySeconds(EntityStopGraceSeconds, () =>
        {
            pendingRemovals.Remove(handle);
            if (!handle.IsValid)
                return;

            DespawnImmediately(handle.Value, reason);
        });
    }

    private void FlushPendingRemovals(string reason)
    {
        var pending = pendingRemovals.ToArray();
        pendingRemovals.Clear();
        foreach (var handle in pending)
        {
            if (handle.IsValid)
                DespawnImmediately(handle.Value, $"pending-flush:{reason}");
        }
    }

    private void DespawnImmediately(
        CParticleSystem? particle,
        string reason)
    {
        if (particle?.IsValidEntity != true)
            return;

        var entityIndex = particle.Index;
        try
        {
            particle.AcceptInput<string>("DestroyImmediately", string.Empty);
            particle.Active = false;
            particle.ActiveUpdated();
        }
        catch (Exception exception)
        {
            Logger.LogDebug(
                exception,
                "MVP particle DestroyImmediately failed for entity {EntityIndex}; " +
                "direct despawn will continue.",
                entityIndex);
        }

        try
        {
            if (particle.IsValidEntity)
                particle.Despawn();

            Logger.LogInformation(
                "MVP_EFFECT_REMOVE entity={EntityIndex} reason={Reason}.",
                entityIndex,
                reason);
        }
        catch (Exception exception)
        {
            Logger.LogWarning(
                exception,
                "Failed to despawn MVP particle entity {EntityIndex}; reason={Reason}.",
                entityIndex,
                reason);
        }
    }

    private MvpEffectConfig LoadConfiguration()
    {
        var path = Path.Combine(Core.PluginPath, ConfigFileName);
        if (!File.Exists(path))
        {
            Logger.LogWarning(
                "MVP config was not found at {Path}; using defaults.",
                path);
            return MvpEffectConfig.Default;
        }

        try
        {
            var loaded = JsonSerializer.Deserialize<MvpEffectConfig>(
                File.ReadAllText(path),
                new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true,
                    AllowTrailingCommas = true,
                    ReadCommentHandling = JsonCommentHandling.Skip
                });
            return MvpEffectConfig.Normalize(loaded);
        }
        catch (Exception exception)
        {
            Logger.LogWarning(
                exception,
                "Failed to load MVP config from {Path}; using defaults.",
                path);
            return MvpEffectConfig.Default;
        }
    }

    private sealed record MvpEffectConfig(
        bool Enabled = true,
        string Audience = "all",
        float Scale = 0.50f,
        float OffsetY = 0.04f)
    {
        public static MvpEffectConfig Default { get; } = new();

        public static MvpEffectConfig Normalize(MvpEffectConfig? value)
        {
            value ??= Default;
            var audience = string.Equals(
                value.Audience,
                "mvp",
                StringComparison.OrdinalIgnoreCase)
                ? "mvp"
                : "all";

            return value with
            {
                Audience = audience,
                Scale = float.IsFinite(value.Scale)
                    ? Math.Clamp(value.Scale, 0.10f, 1.50f)
                    : Default.Scale,
                OffsetY = float.IsFinite(value.OffsetY)
                    ? Math.Clamp(value.OffsetY, -1.0f, 1.0f)
                    : Default.OffsetY
            };
        }
    }

    private sealed class MvpEffectSession(
        int slot,
        CHandle<CParticleSystem>[] particles)
    {
        public int Slot { get; } = slot;
        public CHandle<CParticleSystem>[] Particles { get; } = particles;
    }
}
