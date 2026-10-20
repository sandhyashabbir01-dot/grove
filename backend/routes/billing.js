
const express = require("express");
const crypto = require("crypto");
const authenticate = require("../middleware/auth");
const User = require("../models/User");

const router = express.Router();

const PRICE_IDS = {
  monthly: process.env.STRIPE_GOLD_MONTHLY_PRICE_ID,
  yearly: process.env.STRIPE_GOLD_YEARLY_PRICE_ID,
  business: process.env.STRIPE_BUSINESS_MONTHLY_PRICE_ID,
};

router.get("/status", authenticate, (req, res) => {
  res.json({
    status: req.user.subscriptionStatus || "free",
    plan: req.user.subscriptionPlan || "none",
    periodEnd: req.user.subscriptionPeriodEnd || null,
  });
});

router.post("/checkout", authenticate, async (req, res) => {
  try {
    const plan = String(req.body.plan || "monthly");

    if (!["monthly", "yearly", "business"].includes(plan)) {
      return res.status(400).json({ message: "Unknown plan." });
    }

    const price = PRICE_IDS[plan];

    if (!process.env.STRIPE_SECRET_KEY || !price) {
      return res.status(503).json({
        message:
          "Payments are not configured yet. Add Stripe keys and Price IDs in hosting environment settings. No payment has been taken.",
      });
    }

    const origin = String(req.body.returnOrigin || "").trim();
    const validOrigin =
      /^https:\/\/[a-zA-Z0-9.-]+(?::\d+)?$/.test(origin) ||
      /^http:\/\/localhost(?::\d+)?$/.test(origin);

    if (!validOrigin) {
      return res.status(400).json({
        message: "A valid HTTPS return origin is required.",
      });
    }

    const form = new URLSearchParams({
      mode: "subscription",
      customer_email: req.user.email,
      "line_items[0][price]": price,
      "line_items[0][quantity]": "1",
      success_url: `${origin}/?gold=success`,
      cancel_url: `${origin}/?gold=cancelled`,
      client_reference_id: String(req.user._id),
      "metadata[userId]": String(req.user._id),
      "metadata[plan]": plan,
    });

    const response = await fetch(
      "https://api.stripe.com/v1/checkout/sessions",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${process.env.STRIPE_SECRET_KEY}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: form,
      }
    );

    const data = await response.json();

    if (!response.ok) {
      console.error(
        "Stripe checkout error:",
        data.error?.message || response.status
      );

      return res.status(502).json({
        message: "Payment provider could not start checkout.",
      });
    }

    res.json({ checkoutUrl: data.url });
  } catch (error) {
    console.error("Checkout error:", error.message);
    res.status(500).json({
      message: "Could not start checkout.",
    });
  }
});

// server.js must mount this handler with express.raw() before express.json().
async function webhook(req, res) {
  try {
    const secret = process.env.STRIPE_WEBHOOK_SECRET;
    const signature = req.headers["stripe-signature"];

    if (!secret || !signature || !Buffer.isBuffer(req.body)) {
      return res.status(400).send("Webhook is not configured.");
    }

    const parts = Object.fromEntries(
      signature.split(",").map((part) => {
        const index = part.indexOf("=");
        return [
          part.slice(0, index),
          part.slice(index + 1),
        ];
      })
    );

    const timestamp = parts.t;
    const signatureV1 = parts.v1;

    if (!timestamp || !signatureV1) {
      return res.status(400).send("Invalid signature.");
    }

    // Reject old webhook deliveries to reduce replay risk.
    const ageSeconds = Math.abs(Date.now() / 1000 - Number(timestamp));

    if (!Number.isFinite(ageSeconds) || ageSeconds > 300) {
      return res.status(400).send("Webhook timestamp expired.");
    }

    const signedPayload =
      `${timestamp}.${req.body.toString("utf8")}`;

    const expected = crypto
      .createHmac("sha256", secret)
      .update(signedPayload)
      .digest("hex");

    const expectedBuffer = Buffer.from(expected, "hex");
    const receivedBuffer = Buffer.from(signatureV1, "hex");

    if (
      expectedBuffer.length !== receivedBuffer.length ||
      !crypto.timingSafeEqual(expectedBuffer, receivedBuffer)
    ) {
      return res.status(400).send("Invalid signature.");
    }

    const event = JSON.parse(req.body.toString("utf8"));

    if (event.type === "checkout.session.completed") {
      const session = event.data.object;

      if (
        session.mode === "subscription" &&
        session.metadata?.userId &&
        session.subscription
      ) {
        const allowedPlans = ["monthly", "yearly", "business"];

        await User.findByIdAndUpdate(session.metadata.userId, {
          $set: {
            subscriptionStatus: "active",
            subscriptionPlan: allowedPlans.includes(
              session.metadata.plan
            )
              ? session.metadata.plan
              : "monthly",
            stripeCustomerId: session.customer || null,
            stripeSubscriptionId: session.subscription,
          },
        });
      }
    }

    if (
      event.type === "customer.subscription.deleted" ||
      event.type === "customer.subscription.updated"
    ) {
      const subscription = event.data.object;

      const status =
        event.type === "customer.subscription.deleted"
          ? "cancelled"
          : subscription.status === "active" ||
              subscription.status === "trialing"
            ? "active"
            : subscription.status === "past_due"
              ? "past_due"
              : "cancelled";

      const plan = subscription.metadata?.plan;
      const allowedPlans = ["monthly", "yearly", "business"];

      const update = {
        subscriptionStatus: status,
        subscriptionPeriodEnd: subscription.current_period_end
          ? new Date(subscription.current_period_end * 1000)
          : null,
      };

      if (allowedPlans.includes(plan)) {
        update.subscriptionPlan = plan;
      }

      await User.findOneAndUpdate(
        { stripeSubscriptionId: subscription.id },
        { $set: update }
      );
    }

    return res.json({ received: true });
  } catch (error) {
    console.error("Stripe webhook error:", error.message);
    return res.status(400).send("Webhook handling failed.");
  }
}

module.exports = router;
module.exports.webhook = webhook;
