import type { Request, Response, NextFunction } from "express";
import { authService, registerUser } from "./auth.service";

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

export async function requestPasswordReset(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    const result = await authService.requestPasswordReset(req.body);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function resetPassword(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    const result = await authService.resetPassword(req.body);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function sendOtp(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    const result = await authService.sendOtp(req.auth!.userId, req.body);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function verifyOtp(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    const result = await authService.verifyOtp(req.auth!.userId, req.body);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

