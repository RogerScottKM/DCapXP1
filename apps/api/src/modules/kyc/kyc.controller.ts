import type { Request, Response, NextFunction } from "express";
import { kycService } from "./kyc.service";

export async function getMyKycCase(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await kycService.getMyKycCase(req.auth!.userId);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function createMyKycCase(req: Request, res: Response, next: NextFunction) {
  try {
    const result = await kycService.createMyKycCase(req.auth!.userId);
    res.status(201).json(result);
  } catch (error) {
    next(error);
  }
}
