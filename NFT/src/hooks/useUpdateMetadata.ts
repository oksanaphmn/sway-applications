import { useMutation } from "@tanstack/react-query";
import toast from "react-hot-toast";
import { queryClient } from "@/components/Provider";

// WARNING: although this can take arbitrary metadata
// it overwrites the past metadata
export const useUpdateMetadata = () => {
  const mutation = useMutation({
    mutationFn: async ({
      metadata,
      ipfsHash,
    }: {
      metadata: { name?: string; keyvalues?: { [key: string]: string } };
      ipfsHash: string;
    }) => {
      await fetch("/api/metadata", {
        method: "PUT",
        body: JSON.stringify({ metadata, ipfsHash }),
      });
    },
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["getNFTData"] });
    },
    onError: (err) => {
      toast.error(err.message);
    },
  });

  return mutation;
};
