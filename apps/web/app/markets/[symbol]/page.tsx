import MarketScreen from "@/components/market/MarketScreen";

export const dynamic = "force-dynamic";

export default function MarketPage({ params }: { params: { symbol: string } }) {
  return <MarketScreen symbol={decodeURIComponent(params.symbol)} />;
}
