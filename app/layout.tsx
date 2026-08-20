import type { Metadata } from "next";
import { headers } from "next/headers";
import "./globals.css";

export async function generateMetadata(): Promise<Metadata> {
  const h = await headers();
  const host = h.get("host") ?? "malabna.local";
  const protocol = host.includes("localhost") ? "http" : "https";
  const image = `${protocol}://${host}/og.png`;
  return {
    title: "NextMove | منصتك الرياضية",
    description: "احجز المنشآت الرياضية والتدريب والتغذية والتجهيزات من منصة عراقية واحدة.",
    icons: { icon: "/favicon.svg" },
    openGraph: { title: "NextMove | حركتك القادمة تبدأ هنا", description: "رياضة وحجز وتدريب وتغذية في مكان واحد.", images: [image], locale: "ar_IQ", type: "website" },
    twitter: { card: "summary_large_image", title: "NextMove", description: "حركتك القادمة تبدأ هنا.", images: [image] },
  };
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="ar" dir="rtl"><body>{children}</body></html>;
}
