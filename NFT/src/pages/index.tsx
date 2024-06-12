import { Grid } from "@mui/material";
import { NFTCard } from "@/components/NFTCard";
import { useGetNFTData } from "@/hooks/useGetNFTData";

export default function Home() {
  const { nftData } = useGetNFTData();

  console.log(`nftData`, nftData);

  return (
    <Grid container spacing={2}>
      {nftData?.map((nftDatum) => {
        return (
          <Grid xs={3}>
            <NFTCard
              cid={nftDatum.ipfs_pin_hash}
              fileCid={nftDatum.metadata?.name || ""}
              nftName={nftDatum.metadata.keyvalues?.nftName || ""}
              nftDescription={nftDatum.metadata.keyvalues?.nftDescription || ""}
              nftSubId={nftDatum.metadata.keyvalues?.nftSubId || ""}
            />
          </Grid>
        );
      })}
    </Grid>
  );
}
