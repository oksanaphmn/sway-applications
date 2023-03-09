import { BoxCentered, Button, Flex, Heading, Stack, toast } from "@fuel-ui/react";
import { useState } from "react";
import { useContract } from "../../core/hooks";
import { SignatureComponent } from "../../common/components/signature";
import { InputFieldComponent } from "../../common/components/input_field";
import { InputNumberComponent } from "../../common/components/input_number";
import { OptionalCheckBoxComponent } from "../../common/components/optional_data_checkbox";
import { UserInput } from "../../../contracts/MultisigContractAbi";
import { validateOptionalData } from "../../common/utils/validate_optional_data";
import { validateAddress } from "../../common/utils/validate_address";

export function WeightPage() {
    // Used for our component listeners
    const [address, setAddress] = useState("")
    const [data, setData] = useState("")
    const [weight, setWeight] = useState(0)

    const [optionalData, setOptionalData] = useState(false)
    const [signatures, setSignatures] = useState([<SignatureComponent id={1} name="transfer" />])
    const { contract, isLoading, isError } = useContract()

    async function useWeight() {
        // const signatures = document.querySelector<HTMLInputElement>(
        //     `[name="weight-signatures"]`
        // )!.value;

        let { address: userAddress, isError } = validateAddress(address);
        if (isError) return;

        const { validatedData, isError: error } = validateOptionalData(data);
        if (error) return;

        let user: UserInput = {
            address: userAddress,
            weight: weight
        }

        await contract!.functions.set_weight(validatedData, [], user).call();
        toast.success("Updated user weight!")
    }

    async function addSignature() {
        setSignatures([...signatures, <SignatureComponent id={signatures.length+1} name="weight" /> ]);
    }

    async function removeSignature() {
        if (signatures.length === 1) {
            toast.error("Cannot remove the last signature");
            return;
        }

        setSignatures([...signatures.splice(0, signatures.length - 1)]);
    }

    return (
        <BoxCentered css={{ marginTop: "12%", width: "30%" }}>
            <Stack css={{ minWidth: "100%" }}>
                <Heading as="h3" css={{ marginLeft: "auto", marginRight: "auto", marginBottom: "$10", color: "$accent1" }}>
                    Change approval weight of user
                </Heading>

                <InputFieldComponent onChange={setAddress} text="Recipient address" placeholder="0x80d5e8c2be..." name="weight-address" />
                <InputNumberComponent onChange={setWeight} text="New weight" placeholder="2" name="transaction-value" />

                {signatures.map((signatureComponent, index) => signatureComponent)}

                {optionalData && <InputFieldComponent onChange={setData} text="Optional data" placeholder="0x252afeeb6e..." name="weight-data" />}

                <Button
                    color="accent"
                    onPress={useWeight}
                    size="lg"
                    variant="solid"
                    css={{ marginTop: "$1" }}
                >
                    Set weight
                </Button>

                <Flex gap="$1" css={{ marginTop: "$1" }}>
                    <Button
                        color="accent"
                        onPress={addSignature}
                        size="lg"
                        variant="solid"
                        css={{ width: "50%" }}
                    >
                        Add signature
                    </Button>

                    <Button
                        color="accent"
                        onPress={removeSignature}
                        size="lg"
                        variant="solid"
                        css={{ width: "50%" }}
                    >
                        Remove signature
                    </Button>
                </Flex>

                <OptionalCheckBoxComponent setOptionalData={setOptionalData} optionalData={optionalData} />
            </Stack>
        </BoxCentered>
    );
}
