import { CodegenConfig } from "@graphql-codegen/cli";

// Use actual GraphQL endpoint if available, otherwise fallback to schema file
const GRAPHQL_URL = "https://graphql.mainnet.sui.io/graphql";

const config: CodegenConfig = {
  overwrite: true,
  schema: GRAPHQL_URL,
  // This assumes that all your source files are in a top-level `src/` directory
  documents: ["src/**/*.{ts,tsx}", "!src/gql/**/*"],
  // Don't exit with non-zero status when there are no documents
  ignoreNoDocuments: true,
  generates: {
    // Generate to src/gql/
    "./src/gql/": {
      preset: "client",
      presetConfig: {
        // Disable fragment masking
        fragmentMasking: false,
      },
      config: {
        avoidOptionals: {
          // Use `null` for nullable fields instead of optionals
          field: true,
          // Allow nullable input fields to remain unspecified
          inputValue: false,
        },
        // Use `unknown` instead of `any` for unconfigured scalars
        defaultScalarType: "unknown",
        // Apollo Client always includes `__typename` fields
        nonOptionalTypename: true,
        // Apollo Client doesn't add the `__typename` field to root types so
        // don't generate a type for the `__typename` for root operation types.
        skipTypeNameForRoot: true,
      },
    },
    // Generate schema file for LSP support
    "./src/gql/schema.graphql": {
      plugins: ["schema-ast"],
    },
  },
};

export default config;

