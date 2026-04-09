import express from "express";
import cors from "cors";
import kycRoutes from "./modules/kyc/kyc.routes";
import authRoutes from "./modules/auth/auth.routes";
import onboardingRoutes from "./modules/onboarding/onboarding.routes";
import advisorRoutes from "./modules/advisor/advisor.routes";
import invitationsRoutes from "./modules/invitations/invitations.routes";
import uploadsRoutes from "./modules/uploads/uploads.routes";
import consentsRoutes from "./modules/consents/consents.routes";
import referralsRoutes from "./modules/referrals/referrals.routes";
import marketRoutes from "./routes/market";
import tradeRoutes from "./routes/trade";
import streamRoutes from "./routes/stream";
import verificationRoutes from "./modules/verification/verification.routes";

const app = express();

// Global JSON replacer so Express can safely serialize Prisma BigInt values
app.set("json replacer", (_key: string, value: unknown) => {
  return typeof value === "bigint" ? value.toString() : value;
});

app.use(
  cors({
    origin: [
      "http://localhost:3002",
      "http://localhost:53002",    
    ],
    credentials: true,
  })
);
app.use(express.json());

// health check
app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

// mount feature routes
app.use(onboardingRoutes);
app.use(advisorRoutes);
app.use(consentsRoutes);
app.use(uploadsRoutes);
app.use(invitationsRoutes);


// Everything under /api so frontend calls match
app.use("/api", onboardingRoutes);
app.use("/backend-api", onboardingRoutes);
app.use("/api", advisorRoutes);
app.use("/backend-api", advisorRoutes);
// app.use("/api", invitationsRoutes);
app.use("/api", uploadsRoutes);
app.use("/backend-api", uploadsRoutes);
app.use("/api", consentsRoutes);
app.use("/backend-api", consentsRoutes);
app.use("/api", authRoutes);
app.use("/backend-api", authRoutes);
app.use("/api", kycRoutes);
app.use("/backend-api", kycRoutes);
app.use("/api", referralsRoutes);
app.use("/backend-api", referralsRoutes);

// mount exchange/market routes
app.use(marketRoutes);
app.use(tradeRoutes);
app.use(streamRoutes);

  // exchange / market compatibility mounts
app.use("/v1/market", marketRoutes);
app.use("/api/v1/market", marketRoutes);
app.use("/v1/stream", streamRoutes);
app.use("/api/v1/stream", streamRoutes);

// optional legacy naked mounts for existing local callers
app.use(marketRoutes);
app.use(streamRoutes);
app.use(tradeRoutes);

app.use("/api", verificationRoutes);
app.use("/backend-api", verificationRoutes);

// Global error handler (uses our ApiError)
app.use((err: any, req: express.Request, res: express.Response, next: express.NextFunction) => {
  const status = err.statusCode || 500;
  res.status(status).json({
    error: {
      code: err.code || "INTERNAL_ERROR",
      message: err.message,
      fieldErrors: err.fieldErrors,
      retryable: err.retryable,
    },
  });
});

export default app;