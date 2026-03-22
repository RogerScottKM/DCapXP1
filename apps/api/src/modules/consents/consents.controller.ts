import type { Request, Response, NextFunction } from "express";
import { consentsService } from "./consents.service";
import type { AcceptConsentsRequest } from "@dcapx/contracts";

export async function getRequiredConsents(req: Request, res: Response, next: NextFunction) {
  try {
    const userId = req.auth!.userId;
    const result = await consentsService.getRequiredConsents(userId);
    res.json(result);
  } catch (error) {
    next(error);
  }
}

export async function acceptConsents(req: Request, res: Response, next: NextFunction) {
  try {
    const userId = req.auth!.userId;
    const body = req.body as AcceptConsentsRequest;
    const result = await consentsService.acceptConsents(userId, body);
    res.json(result);
  } catch (error) {
    next(error);
  }
}
