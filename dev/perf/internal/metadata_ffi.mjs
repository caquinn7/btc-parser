const unknown = "unknown";

export function runtimeTarget() {
  return "javascript";
}

export function runtimeVersion() {
  try {
    const denoVersion = globalThis.Deno?.version?.deno;
    if (typeof denoVersion === "string" && denoVersion.length > 0) {
      return `deno ${denoVersion}`;
    }

    const bunVersion = globalThis.Bun?.version;
    if (typeof bunVersion === "string" && bunVersion.length > 0) {
      return `bun ${bunVersion}`;
    }

    const nodeVersion = globalThis.process?.versions?.node;
    if (typeof nodeVersion === "string" && nodeVersion.length > 0) {
      return `node ${nodeVersion}`;
    }
  } catch (_) {
    return unknown;
  }

  return unknown;
}

export function osName() {
  try {
    const denoOs = globalThis.Deno?.build?.os;
    if (typeof denoOs === "string" && denoOs.length > 0) {
      return denoOs;
    }

    const processPlatform = globalThis.process?.platform;
    if (typeof processPlatform === "string" && processPlatform.length > 0) {
      return processPlatform;
    }
  } catch (_) {
    return unknown;
  }

  return unknown;
}

export function architectureName() {
  try {
    const denoArchitecture = globalThis.Deno?.build?.arch;
    if (typeof denoArchitecture === "string" && denoArchitecture.length > 0) {
      return denoArchitecture;
    }

    const processArchitecture = globalThis.process?.arch;
    if (
      typeof processArchitecture === "string" &&
      processArchitecture.length > 0
    ) {
      return processArchitecture;
    }
  } catch (_) {
    return unknown;
  }

  return unknown;
}
