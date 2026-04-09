import type { NextFunction, Request, Response } from "express";
import { referralsService } from "./referrals.service";

export async function applyReferralCode(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    const result = await referralsService.apply(req.auth!.userId, req.body);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function getMyReferralStatus(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    const result = await referralsService.getMyStatus(req.auth!.userId);
    res.json(result);
  } catch (error) {
    next(error);
  }
}
