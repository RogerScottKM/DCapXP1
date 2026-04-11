import type { NextFunction, Request, Response } from "express";

import { authService, registerUser } from "./auth.service";
import { mfaService } from "./mfa.service";

function buildAuditContext(req: Request) {
  return {
    sessionId: req.auth?.sessionId ?? null,
    ipAddress: req.ip ?? null,
    userAgent: req.get("user-agent") ?? null,
  };
}

export async function register(req: Request, res: Response, next: NextFunction) {
  try {
    const user = await registerUser(req.body);
    res.status(201).json({
      ok: true,
      user: {
        id: user.id,
        email: user.email,
        username: user.username,
      },
    });
  } catch (error) {
    next(error);
  }
}

export async function login(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await authService.login(req, res, req.body);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function getSession(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await authService.getSession(req);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function logout(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await authService.logout(req, res);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function requestPasswordReset(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await authService.requestPasswordReset(req.body);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function resetPassword(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await authService.resetPassword(req.body);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function sendOtp(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await authService.sendOtp(req.auth!.userId, req.body);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function verifyOtp(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await authService.verifyOtp(req.auth!.userId, req.body);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function enrollTotp(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await mfaService.beginTotpEnrollment(req.auth!.userId, req.body ?? {}, buildAuditContext(req));
    res.status(201).json(result);
  } catch (error) {
    next(error);
  }
}

export async function activateTotp(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await mfaService.activateTotpEnrollment(
      req.auth!.userId,
      req.auth?.sessionId,
      req.body ?? {},
      buildAuditContext(req),
    );
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function challengeTotp(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await mfaService.challengeTotp(
      req.auth!.userId,
      req.auth?.sessionId,
      req.body ?? {},
      buildAuditContext(req),
    );
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function regenerateRecoveryCodes(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await mfaService.regenerateRecoveryCodes(
      req.auth!.userId,
      req.auth?.sessionId,
      req.body ?? {},
      buildAuditContext(req),
    );
    res.status(201).json(result);
  } catch (error) {
    next(error);
  }
}

export async function challengeRecoveryCode(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await mfaService.challengeRecoveryCode(
      req.auth!.userId,
      req.auth?.sessionId,
      req.body ?? {},
      buildAuditContext(req),
    );
    res.json(result);
  } catch (error) {
    next(error);
  }
}
